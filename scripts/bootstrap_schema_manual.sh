#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <release-root> <env-file>" >&2
  echo "Example: $0 /var/app/newpeople/current /var/app/newpeople/shared/config/api.env" >&2
  exit 1
fi

release_root="$1"
env_file="$2"
schema_path="${release_root}/apps/api/sql/schema.sql"

if [[ ! -f "${env_file}" ]]; then
  echo "Env file not found: ${env_file}" >&2
  exit 1
fi

if [[ ! -f "${schema_path}" ]]; then
  echo "Schema file not found: ${schema_path}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${env_file}"
set +a

required_vars=(DB_HOST DB_PORT DB_NAME DB_USER)
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required DB variable in env file: ${var_name}" >&2
    exit 1
  fi
done

if [[ ! "${DB_NAME}" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Unsupported DB_NAME value: ${DB_NAME}" >&2
  exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
  echo "mysql client is required" >&2
  exit 1
fi

tmp_schema="$(mktemp)"
trap 'rm -f "${tmp_schema}"' EXIT
sed "s/newpeople_crm/${DB_NAME}/g" "${schema_path}" > "${tmp_schema}"

echo "Applying initial schema to ${DB_HOST}:${DB_PORT}/${DB_NAME}"
MYSQL_PWD="${DB_PASSWORD:-}" mysql \
  --host="${DB_HOST}" \
  --port="${DB_PORT}" \
  --user="${DB_USER}" \
  < "${tmp_schema}"

echo "Schema bootstrap completed"
