#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <output-file>" >&2
  exit 1
fi

output_file="$1"

required_vars=(
  PORT
  JWT_SECRET
  JWT_EXPIRES_IN
  APP_INVITE_SETUP_URL
  SMTP_HOST
  SMTP_PORT
  SMTP_SECURE
  SMTP_FROM
  SMTP_USER
  SMTP_PASS
  DB_HOST
  DB_PORT
  DB_NAME
  DB_POOL_SIZE
  DB_USER
  DB_PASSWORD
  OPENAI_MODEL
  OPENAI_BASE_URL
  OPENAI_ENABLE_WEB_SEARCH
  OPENAI_API_KEY
  DOCUMENT_STORAGE_PROVIDER
  DOCUMENT_STORAGE_LOCAL_ROOT
  DOCUMENT_STORAGE_S3_BUCKET
  DOCUMENT_STORAGE_S3_REGION
  DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE
  DOCUMENT_STORAGE_S3_ACCESS_KEY_ID
  DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

write_pair() {
  local key="$1"
  local value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s="%s"\n' "$key" "$value" >> "$output_file"
}

: > "$output_file"

write_pair "PORT" "$PORT"
write_pair "JWT_SECRET" "$JWT_SECRET"
write_pair "JWT_EXPIRES_IN" "$JWT_EXPIRES_IN"
write_pair "APP_INVITE_SETUP_URL" "$APP_INVITE_SETUP_URL"
write_pair "SMTP_HOST" "$SMTP_HOST"
write_pair "SMTP_PORT" "$SMTP_PORT"
write_pair "SMTP_SECURE" "$SMTP_SECURE"
write_pair "SMTP_FROM" "$SMTP_FROM"
write_pair "SMTP_USER" "$SMTP_USER"
write_pair "SMTP_PASS" "$SMTP_PASS"
write_pair "DB_HOST" "$DB_HOST"
write_pair "DB_PORT" "$DB_PORT"
write_pair "DB_NAME" "$DB_NAME"
write_pair "DB_POOL_SIZE" "$DB_POOL_SIZE"
write_pair "DB_USER" "$DB_USER"
write_pair "DB_PASSWORD" "$DB_PASSWORD"
write_pair "OPENAI_MODEL" "$OPENAI_MODEL"
write_pair "OPENAI_BASE_URL" "$OPENAI_BASE_URL"
write_pair "OPENAI_ENABLE_WEB_SEARCH" "$OPENAI_ENABLE_WEB_SEARCH"
write_pair "OPENAI_API_KEY" "$OPENAI_API_KEY"
write_pair "DOCUMENT_STORAGE_PROVIDER" "$DOCUMENT_STORAGE_PROVIDER"
write_pair "DOCUMENT_STORAGE_LOCAL_ROOT" "$DOCUMENT_STORAGE_LOCAL_ROOT"
write_pair "DOCUMENT_STORAGE_S3_BUCKET" "$DOCUMENT_STORAGE_S3_BUCKET"
write_pair "DOCUMENT_STORAGE_S3_REGION" "$DOCUMENT_STORAGE_S3_REGION"
write_pair "DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE" "$DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE"
write_pair "DOCUMENT_STORAGE_S3_ACCESS_KEY_ID" "$DOCUMENT_STORAGE_S3_ACCESS_KEY_ID"
write_pair "DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY" "$DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY"

if [[ -n "${DOCUMENT_STORAGE_S3_ENDPOINT:-}" ]]; then
  write_pair "DOCUMENT_STORAGE_S3_ENDPOINT" "$DOCUMENT_STORAGE_S3_ENDPOINT"
fi