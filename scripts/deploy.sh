#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm.
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=false
case "${1-}" in
    "") ;;
    --dry-run) DRY_RUN=true ;;
    *)
        echo "Использование: ${0} [--dry-run]" >&2
        exit 1
        ;;
esac

if [[ $# -gt 1 ]]; then
    echo "Использование: ${0} [--dry-run]" >&2
    exit 1
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: отсутствует ${LOCAL_DIR}index.html; доставка отменена." >&2
    exit 1
fi

if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения; доставка отменена." >&2
    exit 1
fi

RSYNC_ARGS=(
    -avz
    --delete
    --chmod=D755,F644
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5"
)

if [[ "${DRY_RUN}" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

rsync "${RSYNC_ARGS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

if [[ "${DRY_RUN}" == true ]]; then
    echo "Пробный запуск завершён; сервер не изменён."
    exit 0
fi

if ! curl --fail --silent --show-error --cacert "${CA_CERT}" \
    "${SITE_URL}" -o /dev/null; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен или сертификат не прошёл проверку." >&2
    exit 1
fi

echo "Доставлен коммит $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
