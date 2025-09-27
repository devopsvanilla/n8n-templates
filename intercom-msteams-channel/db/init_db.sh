#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   # optionally create a .env from .env.example and edit it, then:
#   source ../.env  # or rely on script auto-loading .env
#   ./init_db.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# Load .env if present
if [[ -f "$ENV_FILE" ]]; then
  # Export only lines with KEY=VAL, ignore comments/empties; support spaces around =
  while IFS='=' read -r key value; do
    # Trim spaces
    key="${key%%[[:space:]]*}"
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Remove possible quotes around value
    value="${value#*[[:space:]]}"
    value="${value%[[:space:]]*}"
    value="${value%\r}"
    value="${value%\n}"
    value=${value#"\""}
    value=${value%"\""}
    export "$key"="$value"
  done < "$ENV_FILE"
fi

command -v psql >/dev/null 2>&1 || { echo "psql not found. Please install PostgreSQL client."; exit 1; }

PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-postgres}
PGPASSWORD=${PGPASSWORD:-}
DB_NAME=${DB_NAME:-n8n_intercom}

export PGPASSWORD

echo "Connecting to $PGUSER@$PGHOST:$PGPORT, ensuring database '$DB_NAME' exists..."

# Create database if not exists
psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=postgres" \
  -v ON_ERROR_STOP=1 -qtAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=postgres" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$DB_NAME\";"

echo "Applying schema..."
psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$DB_NAME" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/db/init.sql"

echo "Done."
