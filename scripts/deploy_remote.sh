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

run_mysql_database_sql() {
  local sql="$1"

  MYSQL_PWD="${db_password}" mysql \
    --host="${db_host}" \
    --port="${db_port}" \
    --user="${db_user}" \
    "${db_name}" <<EOF
${sql}
EOF
}

ensure_proposal_schema_compatibility() {
  run_mysql_database_sql "
CREATE TABLE IF NOT EXISTS proposal_templates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(80) NOT NULL,
  name VARCHAR(180) NOT NULL,
  status VARCHAR(40) NOT NULL DEFAULT 'draft',
  scope VARCHAR(40) NOT NULL DEFAULT 'global',
  description TEXT NULL,
  preview_title VARCHAR(180) NULL,
  cover_style VARCHAR(40) NOT NULL DEFAULT 'corporate',
  theme_tokens_json LONGTEXT NULL,
  content_defaults_json LONGTEXT NULL,
  section_schema_json LONGTEXT NULL,
  highlight_presets_json LONGTEXT NULL,
  placeholder_rules_json LONGTEXT NULL,
  is_default TINYINT(1) NOT NULL DEFAULT 0,
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  created_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  updated_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  CONSTRAINT uq_proposal_templates_code UNIQUE (code),
  INDEX idx_proposal_templates_status (status, is_default, updated_at),
  CONSTRAINT fk_proposal_templates_created_by FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  CONSTRAINT fk_proposal_templates_updated_by FOREIGN KEY (updated_by_user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS proposals (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  quotation_id BIGINT UNSIGNED NOT NULL,
  quotation_version_id BIGINT UNSIGNED NOT NULL,
  account_id BIGINT UNSIGNED NOT NULL,
  contact_id BIGINT UNSIGNED NOT NULL,
  opportunity_id BIGINT UNSIGNED NOT NULL,
  owner_user_id BIGINT UNSIGNED NOT NULL,
  template_id BIGINT UNSIGNED NULL,
  title VARCHAR(180) NOT NULL,
  status_code VARCHAR(40) NOT NULL DEFAULT 'active',
  content_json LONGTEXT NULL,
  pricing_snapshot_json LONGTEXT NULL,
  template_snapshot_json LONGTEXT NULL,
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  updated_by_user_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  updated_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  archived_at DATETIME(3) NULL,
  CONSTRAINT fk_proposals_quotation FOREIGN KEY (quotation_id) REFERENCES quotations(id) ON DELETE CASCADE,
  CONSTRAINT fk_proposals_quotation_version FOREIGN KEY (quotation_version_id) REFERENCES quotation_versions(id) ON DELETE CASCADE,
  CONSTRAINT fk_proposals_account FOREIGN KEY (account_id) REFERENCES accounts(id),
  CONSTRAINT fk_proposals_contact FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT fk_proposals_opportunity FOREIGN KEY (opportunity_id) REFERENCES opportunities(id),
  CONSTRAINT fk_proposals_owner FOREIGN KEY (owner_user_id) REFERENCES users(id),
  CONSTRAINT fk_proposals_template FOREIGN KEY (template_id) REFERENCES proposal_templates(id) ON DELETE SET NULL,
  CONSTRAINT fk_proposals_created_by FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  CONSTRAINT fk_proposals_updated_by FOREIGN KEY (updated_by_user_id) REFERENCES users(id),
  INDEX idx_proposals_quotation (quotation_id, created_at),
  INDEX idx_proposals_quotation_version (quotation_version_id),
  INDEX idx_proposals_owner (owner_user_id, updated_at),
  INDEX idx_proposals_status (status_code, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS proposal_revisions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  proposal_id BIGINT UNSIGNED NOT NULL,
  revision_number INT NOT NULL,
  quotation_version_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(180) NOT NULL,
  status_code VARCHAR(40) NOT NULL,
  content_json LONGTEXT NULL,
  pricing_snapshot_json LONGTEXT NULL,
  change_type VARCHAR(40) NOT NULL,
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  CONSTRAINT fk_proposal_revisions_proposal FOREIGN KEY (proposal_id) REFERENCES proposals(id) ON DELETE CASCADE,
  CONSTRAINT fk_proposal_revisions_quotation_version FOREIGN KEY (quotation_version_id) REFERENCES quotation_versions(id) ON DELETE CASCADE,
  CONSTRAINT fk_proposal_revisions_created_by FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  CONSTRAINT uq_proposal_revisions_number UNIQUE (proposal_id, revision_number),
  INDEX idx_proposal_revisions_created_at (proposal_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
"
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
ensure_proposal_schema_compatibility

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