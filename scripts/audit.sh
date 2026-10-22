#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит сервера: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход root запрещён" \
    "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" \
    "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "SSH использует нестандартный порт" \
    "2222" "$(sudo sshd -T | awk '/^port/{print $2; exit}')"
check "MaxAuthTries равен 3" \
    "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "UFW активен" \
    "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Входящие соединения запрещены по умолчанию" \
    "deny" "$(sudo ufw status verbose | sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p')"

echo "[3] Учётные записи"
awk -F: '$3 >= 1000 && $3 < 65534 {printf "    %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" \
    "active" "$(systemctl is-active nginx 2>/dev/null)"
check "Конфигурация nginx корректна" \
    "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"

CERT_MIN_VALIDITY_SECONDS="${CERT_MIN_VALIDITY_SECONDS:-2592000}"
check "Сертификат действителен не менее заданного срока" \
    "0" "$(sudo openssl x509 -checkend "${CERT_MIN_VALIDITY_SECONDS}" -noout \
        -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"

if find /var/www/devops-site -perm -o+w -print -quit | grep -q .; then
    WEB_RIGHTS_STATE="world-writable"
else
    WEB_RIGHTS_STATE="safe"
fi
KEY_MODE="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"
check "Файлы сайта защищены, права TLS-ключа равны 600" \
    "safe:600" "${WEB_RIGHTS_STATE}:${KEY_MODE}"

echo "[5] Контейнеризация"
check "Служба docker активна" \
    "active" "$(systemctl is-active docker 2>/dev/null)"
check "Контейнер СУБД находится в состоянии healthy" \
    "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

CONTAINER_LISTENERS="$(sudo ss -H -tln 2>/dev/null \
    | awk '{print $4}' \
    | grep -E ':(5000|5432)$' \
    | sort -u \
    | paste -sd, -)"
check "Порт 5000 доступен только на 127.0.0.1, порт 5432 не опубликован" \
    "127.0.0.1:5000" "${CONTAINER_LISTENERS}"

ENV_MODE="$(stat -c '%a' "$HOME/app/.env" 2>/dev/null)"
check "Права файла ~/app/.env равны 600" \
    "600" "${ENV_MODE}"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
