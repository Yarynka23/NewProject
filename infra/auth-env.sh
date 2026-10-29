#!/usr/bin/env bash
# Writes the Cognito settings from Terraform outputs to .env. Run via `make auth-env`.
# Terraform itself runs only in HCP Terraform; this script only reads its outputs.
set -euo pipefail

set_env() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  if grep -q "^$key=" .env; then
    awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' .env >"$tmp"
  else
    cat .env >"$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  cat "$tmp" >.env
  rm -f "$tmp"
}

main() {
  cd "$(dirname "$0")/.."
  tf() { terraform -chdir=infra output -raw "$1"; }

  set_env COGNITO_USER_POOL_ID "$(tf user_pool_id)"
  set_env COGNITO_CLIENT_ID "$(tf user_pool_client_id)"
  set_env COGNITO_DOMAIN "$(tf cognito_domain)"
  set_env COGNITO_GOOGLE_ENABLED "$(tf google_enabled)"
  echo "Cognito settings written to .env"
}

main "$@"
