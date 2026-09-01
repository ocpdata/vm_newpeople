#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <output-file>" >&2
  exit 1
fi

output_file="$1"

required_vars=(
  PORT
  TZ
  JWT_SECRET
  JWT_EXPIRES_IN
  APP_BASE_URL
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
  AUTH_GOOGLE_ENABLED
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

case "${DOCUMENT_STORAGE_PROVIDER}" in
  local)
    if [[ -z "${DOCUMENT_STORAGE_LOCAL_ROOT:-}" ]]; then
      echo "Missing required environment variable: DOCUMENT_STORAGE_LOCAL_ROOT" >&2
      exit 1
    fi
    ;;
  s3|s3_compatible)
    storage_vars=(
      DOCUMENT_STORAGE_S3_BUCKET
      DOCUMENT_STORAGE_S3_REGION
      DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE
      DOCUMENT_STORAGE_S3_ACCESS_KEY_ID
      DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY
    )

    for var_name in "${storage_vars[@]}"; do
      if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: ${var_name}" >&2
        exit 1
      fi
    done
    ;;
  *)
    echo "Unsupported DOCUMENT_STORAGE_PROVIDER: ${DOCUMENT_STORAGE_PROVIDER}" >&2
    exit 1
    ;;
esac

write_pair() {
  local key="$1"
  local value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s="%s"\n' "$key" "$value" >> "$output_file"
}

: > "$output_file"

write_pair "PORT" "$PORT"
write_pair "TZ" "$TZ"
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

case "${DOCUMENT_STORAGE_PROVIDER}" in
  local)
    write_pair "DOCUMENT_STORAGE_LOCAL_ROOT" "$DOCUMENT_STORAGE_LOCAL_ROOT"
    ;;
  s3|s3_compatible)
    write_pair "DOCUMENT_STORAGE_S3_BUCKET" "$DOCUMENT_STORAGE_S3_BUCKET"
    write_pair "DOCUMENT_STORAGE_S3_REGION" "$DOCUMENT_STORAGE_S3_REGION"
    write_pair "DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE" "$DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE"
    write_pair "DOCUMENT_STORAGE_S3_ACCESS_KEY_ID" "$DOCUMENT_STORAGE_S3_ACCESS_KEY_ID"
    write_pair "DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY" "$DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY"

    if [[ -n "${DOCUMENT_STORAGE_S3_ENDPOINT:-}" ]]; then
      write_pair "DOCUMENT_STORAGE_S3_ENDPOINT" "$DOCUMENT_STORAGE_S3_ENDPOINT"
    fi
    ;;
esac

write_pair "APP_BASE_URL" "$APP_BASE_URL"
write_pair "AUTH_GOOGLE_ENABLED" "$AUTH_GOOGLE_ENABLED"

if [[ "${AUTH_GOOGLE_ENABLED}" == "true" ]]; then
  google_vars=(GOOGLE_CLIENT_ID GOOGLE_REDIRECT_URI GOOGLE_CLIENT_SECRET)
  for var_name in "${google_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      echo "Missing required environment variable: ${var_name}" >&2
      exit 1
    fi
  done

  write_pair "GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_ID"
  write_pair "GOOGLE_REDIRECT_URI" "$GOOGLE_REDIRECT_URI"
  write_pair "GOOGLE_CLIENT_SECRET" "$GOOGLE_CLIENT_SECRET"
fi

# Optional F5 XC WAF test integration: only written when all pieces are configured.
waf_vars=(WAF_LOGIN_EMAIL WAF_LOGIN_PASSWORD XC_API_URL XC_API_P12_FILE XC_P12_PASSWORD XC_NAMESPACE XC_LB_NAME XC_WAF_MODE)
waf_configured=true
for var_name in "${waf_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    waf_configured=false
    break
  fi
done
if [[ "${waf_configured}" == "true" ]]; then
  for var_name in "${waf_vars[@]}"; do
    write_pair "$var_name" "${!var_name}"
  done
fi

if [[ -n "${K6_CLOUD_TOKEN:-}" ]]; then
  write_pair "K6_CLOUD_TOKEN" "$K6_CLOUD_TOKEN"
fi

if [[ -n "${K6_CLOUD_STACK_ID:-}" ]]; then
  write_pair "K6_CLOUD_STACK_ID" "$K6_CLOUD_STACK_ID"
fi