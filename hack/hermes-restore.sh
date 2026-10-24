#!/usr/bin/env bash
# Restore a Hermes backup into the running Hermes, then restart it.
#   hack/hermes-restore.sh [hermes-backup-<date>.zip]
# Get the zip with: gh release download <tag> -R Abhishek-1804/hermes-backups
set -euo pipefail

zip=${1:-}   # without one, only the secret checks and restart below run
k() { kubectl --kubeconfig "${KUBECONFIG:-.kube/kubeconfig-server}" -n ai "$@"; }   # or export KUBECONFIG

pod=$(k get pods -l app=hermes-agent -o jsonpath='{.items[0].metadata.name}')
if [ -n "$zip" ]; then
    k cp "$zip" "$pod:/tmp/backup.zip"
    k exec "$pod" -- hermes import --force /tmp/backup.zip
fi

# 1Password's secrets (from the Kubernetes Secret) must win: drop any the backup
# holds, and keep multiplexing off. Keep this list in sync with the
# secretKeyRef entries in manifests/ai/hermes-agent.yaml.
for key in CLAUDE_CODE_OAUTH_TOKEN HERMES_BACKUP_PAT \
           HERMES_DASHBOARD_BASIC_AUTH_PASSWORD HERMES_DASHBOARD_BASIC_AUTH_SECRET; do
    k exec "$pod" -- hermes config unset "$key" || true   # "not set" is fine
done
k exec "$pod" -- hermes config set gateway.multiplex_profiles false

k rollout restart deploy/hermes-agent
k rollout status deploy/hermes-agent
