#!/bin/bash
# Run a SQL file against the reader database from the libnode-deployer .env file.
# Usage: ./run-sql.sh <sql-file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
SQL_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

# Load the connection string from .env
DB_CONNECTION_STRING=""
while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  # Remove surrounding quotes from value
  value="${value%\"}"
  value="${value#\"}"
  if [[ "$key" == "DB_CONNECTION_STRING" ]]; then
    DB_CONNECTION_STRING="$value"
    break
  fi
done < "$ENV_FILE"

if [[ -z "$DB_CONNECTION_STRING" ]]; then
  echo "DB_CONNECTION_STRING not found in $ENV_FILE" >&2
  exit 1
fi

# Parse key-value pairs
parse_conn_str() {
  local conn_str="$1"
  local key="$2"
  echo "$conn_str" | tr ';' '\n' | grep -i "^$key=" | cut -d= -f2- | head -n1
}

HOST=$(parse_conn_str "$DB_CONNECTION_STRING" "Host")
PORT=$(parse_conn_str "$DB_CONNECTION_STRING" "Port")
DATABASE=$(parse_conn_str "$DB_CONNECTION_STRING" "Database")
USERNAME=$(parse_conn_str "$DB_CONNECTION_STRING" "Username")
PASSWORD=$(parse_conn_str "$DB_CONNECTION_STRING" "Password")

PORT="${PORT:-5432}"

export PGPASSWORD="$PASSWORD"

docker run --rm --network libnode-deployer_default \
  -e PGPASSWORD \
  -v "$SQL_FILE:/tmp/sql.sql:ro" \
  postgres:16-alpine \
  psql -h "$HOST" -p "$PORT" -U "$USERNAME" -d "$DATABASE" -f /tmp/sql.sql

unset PGPASSWORD
