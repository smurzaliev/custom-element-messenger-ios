#!/usr/bin/env bash
# Проверка корректности развёртывания Universal Links / App Links на ucmatrix.org
# Запускать ПОСЛЕ деплоя файлов в /.well-known/
#
# Использование:  bash verify.sh
# Требуется: curl, jq (опционально)

set -u

DOMAIN="ucmatrix.org"
EXPECTED_APP_ID="6HRG779SDK.org.ucmeet.UCMeetChat"

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
header() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

fail=0

check_url() {
    local url="$1"
    local label="$2"

    header "$label"
    echo "URL: $url"

    local headers
    headers=$(curl -sI "$url") || { red "  ОШИБКА: curl упал"; fail=$((fail+1)); return; }

    local status
    status=$(printf '%s' "$headers" | head -1 | awk '{print $2}')
    local content_type
    content_type=$(printf '%s' "$headers" | grep -i '^content-type:' | head -1 | sed 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//' | tr -d '\r')

    if [[ "$status" == "200" ]]; then
        green "  HTTP 200 OK"
    else
        red "  ОШИБКА: HTTP $status (ожидается 200)"
        fail=$((fail+1))
    fi

    if [[ "$content_type" == application/json* ]]; then
        green "  Content-Type: $content_type"
    else
        red "  ОШИБКА: Content-Type = '$content_type' (ожидается application/json)"
        fail=$((fail+1))
    fi

    if printf '%s' "$headers" | grep -qi '^location:'; then
        red "  ОШИБКА: Найден редирект (Location header). Apple/Google молча отбросят файл."
        fail=$((fail+1))
    fi
}

check_url "https://$DOMAIN/.well-known/apple-app-site-association" "iOS — apple-app-site-association"

# Содержимое AASA: проверяем appIDs
header "iOS — содержимое AASA"
aasa_body=$(curl -s "https://$DOMAIN/.well-known/apple-app-site-association")
if printf '%s' "$aasa_body" | grep -q "$EXPECTED_APP_ID"; then
    green "  appID '$EXPECTED_APP_ID' присутствует"
else
    red "  ОШИБКА: appID '$EXPECTED_APP_ID' не найден в AASA"
    fail=$((fail+1))
fi

check_url "https://$DOMAIN/.well-known/assetlinks.json" "Android — assetlinks.json"

# Содержимое assetlinks: проверяем заглушки
header "Android — содержимое assetlinks.json"
android_body=$(curl -s "https://$DOMAIN/.well-known/assetlinks.json")
if printf '%s' "$android_body" | grep -q "REPLACE_WITH_"; then
    yellow "  ВНИМАНИЕ: в assetlinks.json остались заглушки REPLACE_WITH_..."
    yellow "  Android-разработчик должен прислать package_name и SHA-256 fingerprint."
fi

header "Внешний валидатор Apple"
echo "Откройте в браузере и введите домен ucmatrix.org:"
echo "  https://branch.io/resources/aasa-validator/"

header "ИТОГ"
if [[ $fail -eq 0 ]]; then
    green "Все обязательные проверки пройдены."
    exit 0
else
    red "Найдено ошибок: $fail. Исправьте и запустите проверку снова."
    exit 1
fi
