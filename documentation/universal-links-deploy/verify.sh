#!/usr/bin/env bash
# Проверка корректности развёртывания Universal Links / App Links на ucmatrix.org
# Запускать ПОСЛЕ деплоя файлов в /.well-known/
#
# Использование:  bash verify.sh
# Требуется: curl, jq (опционально)

set -u

DOMAIN="ucmatrix.org"
EXPECTED_APP_ID="6HRG779SDK.org.ucmeet.UCMeetChat"
EXPECTED_ANDROID_PACKAGE="org.ucmeet.chat"

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
    headers=$(curl -sI "$url") || { red "  ОШИБКА: curl упал (нет сети или DNS)"; fail=$((fail+1)); return; }

    local status
    status=$(printf '%s' "$headers" | head -1 | awk '{print $2}')
    local content_type
    content_type=$(printf '%s' "$headers" | grep -i '^content-type:' | head -1 | sed 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//' | tr -d '\r')

    local local_failed=0

    if [[ "$status" == "200" ]]; then
        green "  HTTP 200 OK"
    else
        red "  ОШИБКА: HTTP $status (ожидается 200)"
        local_failed=1
    fi

    if [[ "$content_type" == application/json* ]]; then
        green "  Content-Type: $content_type"
    else
        red "  ОШИБКА: Content-Type = '$content_type' (ожидается application/json)"
        local_failed=1
    fi

    if printf '%s' "$headers" | grep -qi '^location:'; then
        red "  ОШИБКА: Найден редирект (Location header). Apple/Google молча отбросят файл."
        local_failed=1
    fi

    # При ошибке — печатаем сырые заголовки, чтобы ops мог быстро разобраться
    if [[ $local_failed -ne 0 ]]; then
        yellow "  --- Сырые заголовки ответа ---"
        printf '%s\n' "$headers" | sed 's/^/    /'
        yellow "  ------------------------------"
        fail=$((fail+local_failed))
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

# Содержимое assetlinks: проверяем package и наличие SHA-256
header "Android — содержимое assetlinks.json"
android_body=$(curl -s "https://$DOMAIN/.well-known/assetlinks.json")
if printf '%s' "$android_body" | grep -q "\"$EXPECTED_ANDROID_PACKAGE\""; then
    green "  package_name '$EXPECTED_ANDROID_PACKAGE' присутствует"
else
    red "  ОШИБКА: package_name '$EXPECTED_ANDROID_PACKAGE' не найден в assetlinks.json"
    fail=$((fail+1))
fi
if printf '%s' "$android_body" | grep -qE '[0-9A-F]{2}(:[0-9A-F]{2}){31}'; then
    green "  SHA-256 fingerprint присутствует (формат корректен)"
else
    red "  ОШИБКА: SHA-256 fingerprint не найден или неправильный формат"
    fail=$((fail+1))
fi
if printf '%s' "$android_body" | grep -q "REPLACE_WITH_"; then
    yellow "  ВНИМАНИЕ: в assetlinks.json остались заглушки REPLACE_WITH_..."
    fail=$((fail+1))
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
