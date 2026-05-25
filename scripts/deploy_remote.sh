#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <release-archive> <env-file> <release-id>" >&2
  exit 1
fi

archive_path="$1"
env_path="$2"
release_id="$3"

app_root="/var/app/newpeople"
shared_root="${app_root}/shared"
release_root="${app_root}/releases/${release_id}"
current_link="${app_root}/current"
shared_env="${shared_root}/config/api.env"
service_path="/etc/systemd/system/newpeople-api.service"
nginx_site="/etc/nginx/sites-available/newpeople.conf"
nginx_enabled="/etc/nginx/sites-enabled/newpeople.conf"

read_env_value() {
  local key="$1"
  local value

  value="$(sudo grep "^${key}=" "${shared_env}" | cut -d= -f2- || true)"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

print_service_diagnostics() {
  echo "===== systemctl status =====" >&2
  sudo systemctl status newpeople-api --no-pager >&2 || true
  echo "===== journalctl =====" >&2
  sudo journalctl -u newpeople-api -n 200 --no-pager >&2 || true
}

wait_for_local_health() {
  local health_url="$1"

  for attempt in {1..12}; do
    if curl --fail --show-error --silent "$health_url"; then
      echo >&2
      return 0
    fi

    echo "Waiting for API healthcheck on ${health_url} (attempt ${attempt}/12)..." >&2
    sleep 5
  done

  echo "API healthcheck did not become ready on ${health_url}" >&2
  print_service_diagnostics
  return 1
}

sudo mkdir -p "${release_root}"
sudo tar -xzf "${archive_path}" -C "${release_root}"
sudo chown -R "$USER":"$USER" "${release_root}"

sudo install -m 0600 -o root -g root "${env_path}" "${shared_env}"

pushd "${release_root}" >/dev/null
npm install
popd >/dev/null

db_host="$(read_env_value DB_HOST)"
db_port="$(read_env_value DB_PORT)"
db_name="$(read_env_value DB_NAME)"
db_user="$(read_env_value DB_USER)"
db_password="$(read_env_value DB_PASSWORD)"

if [[ -z "${db_host}" || -z "${db_port}" || -z "${db_name}" || -z "${db_user}" ]]; then
  echo "Missing DB connection values in ${shared_env}" >&2
  exit 1
fi

if [[ ! "${db_name}" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Unsupported DB_NAME value: ${db_name}" >&2
  exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y mysql-client
fi

schema_temp="$(mktemp)"
trap 'rm -f "${schema_temp}"' EXIT
sed "s/newpeople_crm/${db_name}/g" "${release_root}/apps/api/sql/schema.sql" > "${schema_temp}"
MYSQL_PWD="${db_password}" mysql \
  --host="${db_host}" \
  --port="${db_port}" \
  --user="${db_user}" \
  < "${schema_temp}"

api_port="$(sudo grep '^PORT=' "${shared_env}" | cut -d= -f2-)"
api_port="${api_port#\"}"
api_port="${api_port%\"}"
if [[ -z "${api_port}" ]]; then
  api_port="4000"
fi

cat <<EOF | sudo tee "${service_path}" >/dev/null
[Unit]
Description=NewPeople API
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=${current_link}
Environment=NODE_ENV=production
EnvironmentFile=${shared_env}
ExecStart=/usr/bin/npm run start --prefix apps/api
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee "${nginx_site}" >/dev/null
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root ${current_link}/apps/web/dist;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:${api_port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /health {
        proxy_pass http://127.0.0.1:${api_port}/health;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

sudo ln -sfn "${release_root}" "${current_link}"
sudo ln -sfn "${nginx_site}" "${nginx_enabled}"
sudo rm -f /etc/nginx/sites-enabled/default

sudo systemctl daemon-reload
sudo systemctl enable newpeople-api
sudo systemctl restart newpeople-api
wait_for_local_health "http://127.0.0.1:${api_port}/health"
sudo nginx -t
sudo systemctl reload nginx