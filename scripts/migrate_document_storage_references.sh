#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <source-bucket> <destination-bucket> <env-file>" >&2
  exit 1
fi

source_bucket="$1"
destination_bucket="$2"
env_file="$3"
app_root="/var/app/newpeople/current"
dry_run="${MIGRATION_DRY_RUN:-false}"

if [[ ! "$source_bucket" =~ ^[a-z0-9.-]+$ || ! "$destination_bucket" =~ ^[a-z0-9.-]+$ ]]; then
  echo "Unsupported S3 bucket name." >&2
  exit 1
fi

if [[ "$dry_run" != "true" && "$dry_run" != "false" ]]; then
  echo "MIGRATION_DRY_RUN must be true or false." >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo "Environment file not found: $env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

required_vars=(
  DB_HOST
  DB_PORT
  DB_NAME
  DB_USER
  DOCUMENT_STORAGE_S3_REGION
  DOCUMENT_STORAGE_S3_ACCESS_KEY_ID
  DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required variable in environment file: $var_name" >&2
    exit 1
  fi
done

if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Unsupported DB_NAME value: $DB_NAME" >&2
  exit 1
fi

references_file="$(mktemp)"
verified_ids_file="$(mktemp)"
missing_keys_file="$(mktemp)"
trap 'rm -f "$references_file" "$verified_ids_file" "$missing_keys_file"' EXIT

storage_tables=(
  documents
  campaign_email_shared_documents
  commercial_enablement_assets
  commercial_enablement_intake_sessions
  commercial_enablement_item_files
)

reference_query=""
for table_name in "${storage_tables[@]}"; do
  if [[ -n "$reference_query" ]]; then
    reference_query+=" UNION ALL "
  fi
  reference_query+="SELECT '${table_name}', id, CONVERT(storage_key USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ${table_name} WHERE storage_bucket = '${source_bucket}'"
done
reference_query+=" ORDER BY 1, 2;"

MYSQL_PWD="${DB_PASSWORD:-}" mysql \
  --batch \
  --skip-column-names \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --user="$DB_USER" \
  "$DB_NAME" \
  --execute="$reference_query" \
  > "$references_file"

chown deployer:deployer "$references_file" "$verified_ids_file" "$missing_keys_file"
chmod 0600 "$references_file" "$verified_ids_file" "$missing_keys_file"

cd "$app_root"
sudo -u deployer env \
  DOCUMENT_STORAGE_S3_REGION="$DOCUMENT_STORAGE_S3_REGION" \
  DOCUMENT_STORAGE_S3_ACCESS_KEY_ID="$DOCUMENT_STORAGE_S3_ACCESS_KEY_ID" \
  DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY="$DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY" \
  REFERENCES_FILE="$references_file" \
  VERIFIED_IDS_FILE="$verified_ids_file" \
  MISSING_KEYS_FILE="$missing_keys_file" \
  DESTINATION_BUCKET="$destination_bucket" \
  node --input-type=module <<'NODE'
import { readFile, writeFile } from "node:fs/promises";
import { HeadBucketCommand, HeadObjectCommand, S3Client } from "@aws-sdk/client-s3";

const rows = (await readFile(process.env.REFERENCES_FILE, "utf8"))
  .split("\n")
  .filter(Boolean)
  .map((line) => {
    const [table, id, ...keyParts] = line.split("\t");
    return { table, id, key: keyParts.join("\t") };
  });
const client = new S3Client({
  region: process.env.DOCUMENT_STORAGE_S3_REGION,
  credentials: {
    accessKeyId: process.env.DOCUMENT_STORAGE_S3_ACCESS_KEY_ID,
    secretAccessKey: process.env.DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY,
  },
});
const verifiedIds = [];
const missingKeys = [];

await client.send(new HeadBucketCommand({ Bucket: process.env.DESTINATION_BUCKET }));

for (const row of rows) {
  try {
    await client.send(new HeadObjectCommand({
      Bucket: process.env.DESTINATION_BUCKET,
      Key: row.key,
    }));
    verifiedIds.push(`${row.table}\t${row.id}`);
  } catch (error) {
    if (error?.$metadata?.httpStatusCode === 404 || error?.name === "NotFound" || error?.name === "NoSuchKey") {
      missingKeys.push(`${row.table}\t${row.key}`);
    } else {
      throw error;
    }
  }
}

await writeFile(process.env.VERIFIED_IDS_FILE, verifiedIds.join("\n"));
await writeFile(process.env.MISSING_KEYS_FILE, missingKeys.join("\n"));
console.log(JSON.stringify({
  references: rows.length,
  verified: verifiedIds.length,
  missing: missingKeys.length,
}));
NODE

reference_count="$(wc -l < "$references_file" | tr -d ' ')"
verified_count="$(grep -c . "$verified_ids_file" || true)"
missing_count="$(grep -c . "$missing_keys_file" || true)"

if (( verified_count > 0 )) && [[ "$dry_run" == "false" ]]; then
  migration_id="s3-${source_bucket}-to-${destination_bucket}"

  MYSQL_PWD="${DB_PASSWORD:-}" mysql \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --user="$DB_USER" \
    "$DB_NAME" <<SQL
CREATE TABLE IF NOT EXISTS storage_bucket_migration_backup (
  migration_id VARCHAR(255) NOT NULL,
  source_table VARCHAR(64) NOT NULL,
  record_id BIGINT UNSIGNED NOT NULL,
  storage_key VARCHAR(500) NOT NULL,
  previous_storage_bucket VARCHAR(120) NULL,
  destination_storage_bucket VARCHAR(120) NOT NULL,
  migrated_at DATETIME(3) NOT NULL DEFAULT NOW(3),
  PRIMARY KEY (migration_id, source_table, record_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL

  for table_name in "${storage_tables[@]}"; do
    ids_csv="$(awk -F '\t' -v table="$table_name" '$1 == table { print $2 }' "$verified_ids_file" | paste -sd, -)"
    if [[ -z "$ids_csv" ]]; then
      continue
    fi

    MYSQL_PWD="${DB_PASSWORD:-}" mysql \
      --host="$DB_HOST" \
      --port="$DB_PORT" \
      --user="$DB_USER" \
      "$DB_NAME" <<SQL
START TRANSACTION;
INSERT IGNORE INTO storage_bucket_migration_backup (
  migration_id,
  source_table,
  record_id,
  storage_key,
  previous_storage_bucket,
  destination_storage_bucket
)
SELECT
  '${migration_id}',
  '${table_name}',
  id,
  storage_key,
  storage_bucket,
  '${destination_bucket}'
FROM ${table_name}
WHERE storage_bucket = '${source_bucket}'
  AND id IN (${ids_csv});

UPDATE ${table_name}
SET storage_bucket = '${destination_bucket}'
WHERE storage_bucket = '${source_bucket}'
  AND id IN (${ids_csv});
COMMIT;
SQL
  done
fi

remaining_query=""
for table_name in "${storage_tables[@]}"; do
  if [[ -n "$remaining_query" ]]; then
    remaining_query+=" UNION ALL "
  fi
  remaining_query+="SELECT COUNT(*) AS count FROM ${table_name} WHERE storage_bucket = '${source_bucket}'"
done

remaining_count="$(MYSQL_PWD="${DB_PASSWORD:-}" mysql \
  --batch \
  --skip-column-names \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --user="$DB_USER" \
  "$DB_NAME" \
  --execute="SELECT SUM(count) FROM (${remaining_query}) AS remaining_references;")"

echo "Storage references found: $reference_count"
if [[ "$dry_run" == "true" ]]; then
  echo "Storage references eligible for update: $verified_count"
else
  echo "Storage references updated: $verified_count"
fi
echo "Storage references left on source bucket: $remaining_count"

if (( missing_count > 0 )); then
  echo "::warning::$missing_count objects are missing from the destination bucket; their RDS references remain unchanged."
fi