#!/usr/bin/env bash
# Install deploy SSH private key + pinned known_hosts from secrets.
set -euo pipefail

key="$(printf '%s' "${DEPLOY_SSH_KEY:?DEPLOY_SSH_KEY is empty}" | tr -d '\r')"
install -d -m 700 "${HOME}/.ssh"
KEY_FILE="${HOME}/.ssh/supply-chain-deploy"
KNOWN_HOSTS_FILE="${HOME}/.ssh/supply-chain-known_hosts"

printf '%s\n' "$key" > "${KEY_FILE}"
chmod 600 "${KEY_FILE}"

if ! ssh-keygen -y -f "${KEY_FILE}" >/dev/null 2>&1; then
  echo "DEPLOY_SSH_KEY does not parse as a private key."
  echo "Paste the PRIVATE key (BEGIN OPENSSH/RSA PRIVATE KEY), not the .pub."
  exit 1
fi

known="$(printf '%s' "${DEPLOY_SSH_KNOWN_HOSTS:-}" | tr -d '\r')"
if [ -z "${known}" ]; then
  echo "DEPLOY_SSH_KNOWN_HOSTS is empty."
  echo "Generate on a trusted machine:"
  echo "  ssh-keyscan -p \"\$DEPLOY_SSH_PORT\" \"\$DEPLOY_SSH_HOST\""
  echo "Store the full output as environment secret DEPLOY_SSH_KNOWN_HOSTS (production)."
  exit 1
fi

printf '%s\n' "${known}" > "${KNOWN_HOSTS_FILE}"
chmod 644 "${KNOWN_HOSTS_FILE}"

if ! grep -qE '^[^\s#]+' "${KNOWN_HOSTS_FILE}"; then
  echo "DEPLOY_SSH_KNOWN_HOSTS has no usable host key lines."
  exit 1
fi

{
  echo "KEY_FILE=${KEY_FILE}"
  echo "KNOWN_HOSTS_FILE=${KNOWN_HOSTS_FILE}"
} >> "${GITHUB_ENV}"

echo "deploy key + known_hosts installed OK"
