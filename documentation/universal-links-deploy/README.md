# Развёртывание Universal Links (iOS) и App Links (Android) на ucmatrix.org

> **Получатель:** команда, которая сопровождает домен `ucmatrix.org`.
>
> **Что это даёт:** после развёртывания этих двух файлов тап по ссылке вида `https://ucmatrix.org/#/room/...` в Telegram, Mail, Safari и других приложениях будет открывать её **прямо внутри UCMeet.Chat** (на iOS и Android), а не в браузере.
>
> **Почему один и тот же конфиг покрывает обе платформы:** iOS и Android используют разные файлы, но оба ищут их по одному и тому же фиксированному пути `/.well-known/` на корневом домене. Поэтому один деплой в `/.well-known/` закрывает вопрос «симлинков» сразу для двух приложений.

---

## Содержимое пакета

| Файл | Назначение | Что с ним делать |
|---|---|---|
| `apple-app-site-association` | Манифест для iOS (готов) | Залить как есть |
| `assetlinks.json` | Манифест для Android (готов, заполнен данными от Android-команды) | Залить как есть. **Внимание:** содержит DEBUG SHA-256 — после публикации в Google Play файл нужно будет перевыпустить с production-ключом (см. ниже) |
| `nginx-snippet.conf` | Пример конфигурации веб-сервера (nginx + Apache + Caddy + S3) | Адаптировать под вашу конфигурацию |
| `verify.sh` | Скрипт проверки после деплоя | Запустить, убедиться что всё ОК |
| `README.md` | Этот файл | — |

> ⚠️ **Важно про Android SHA-256.**
> В текущей версии `assetlinks.json` указан DEBUG-сертификат Android-приложения — этого достаточно для тестирования и для сборок, которые ставятся напрямую (не через Google Play). После того как Android-приложение будет опубликовано в Google Play, Play App Signing **перевыпускает ключ**, и SHA-256 у установленного из стора приложения будет другим. В этот момент Android-разработчик пришлёт новый `assetlinks.json` с production-fingerprint из Play Console (App Signing → "App signing key certificate"), и его нужно будет залить вместо текущего файла. До этого момента App Links будут работать только для билдов, подписанных текущим debug-ключом.

---

## Шаг 1. Развернуть iOS-файл

**Целевой URL:** `https://ucmatrix.org/.well-known/apple-app-site-association`

Файл `apple-app-site-association` из этого пакета залить **как есть** (уже содержит правильный App ID `6HRG779SDK.org.ucmeet.UCMeetChat`).

**Жёсткие требования Apple — отклонения приведут к молчаливому отказу:**

| Требование | Значение |
|---|---|
| Протокол | Только `https://` (валидный TLS-сертификат) |
| Точный путь | `/.well-known/apple-app-site-association` (БЕЗ расширения `.json` в имени!) |
| `Content-Type` | `application/json` |
| HTTP-статус | `200 OK` (никаких редиректов 301/302) |
| Размер | < 128 KB |

---

## Шаг 2. Развернуть Android-файл

**Целевой URL:** `https://ucmatrix.org/.well-known/assetlinks.json`

Файл `assetlinks.json` из этого пакета залить **как есть**. Он уже заполнен данными от Android-команды:

| Поле | Значение |
|---|---|
| `package_name` | `org.ucmeet.chat` |
| `sha256_cert_fingerprints[0]` | `B0:B0:51:DC:56:5C:81:2F:E1:7F:6F:3E:94:5B:4D:79:04:71:23:AB:0D:A6:12:86:76:9E:B2:94:91:97:13:0E` (DEBUG) |

**Требования Google такие же, как у Apple** (HTTPS, 200 OK, `application/json`, без редиректов). Расширение `.json` здесь обязательно.

> 🔁 **Этот файл нужно будет обновить один раз после публикации в Google Play.**
> Текущий fingerprint — debug-ключа. После публикации Play App Signing назначит новый ключ, и Android-разработчик пришлёт обновлённый `assetlinks.json` с production SHA-256 из Play Console. Замена — перезалить файл по тому же URL. App Links на устройствах активируются автоматически после следующего обновления приложения из стора (Google Play периодически перепроверяет `assetlinks.json`).

---

## Шаг 3. Конфигурация веб-сервера

См. `nginx-snippet.conf` — там пример для **nginx** + краткие шпаргалки для **Apache (.htaccess)**, **Caddy** и **AWS S3 + CloudFront**.

Главные правила одинаковы для любого сервера:

- Файлы отдаются с `Content-Type: application/json`.
- Никаких редиректов с `/.well-known/...`. Часто `.well-known/` уже перехватывается ACME/Let's Encrypt — наши блоки должны быть определены **после** общего, иначе сервер выберет более общий блок и Content-Type будет неправильный.
- Если перед сервером CDN (CloudFlare, CloudFront и т.п.) — убедиться, что CDN не подменяет Content-Type и не добавляет редиректы.

---

## Шаг 4. Проверка деплоя

```bash
bash verify.sh
```

Скрипт делает `curl` к обоим URL, проверяет HTTP-статус, Content-Type, отсутствие редиректов и наличие правильного App ID в AASA.

Дополнительная проверка через внешний валидатор Apple:
- https://branch.io/resources/aasa-validator/ → ввести `ucmatrix.org`, выбрать **Production** → должен показать success для App ID `6HRG779SDK.org.ucmeet.UCMeetChat`.

Ручная проверка через `curl` (без скрипта):

```bash
# iOS
curl -I https://ucmatrix.org/.well-known/apple-app-site-association
# Android
curl -I https://ucmatrix.org/.well-known/assetlinks.json
```

В обоих ответах должно быть:
```
HTTP/2 200
content-type: application/json
```

---

## Подводные камни

- **Кеш Apple до 24 часов.** Если первый запрос AASA вернул ошибку (например, неправильный Content-Type), iOS закеширует «нет домена» на этом устройстве **до 24 часов**. Поэтому сначала разворачиваем правильный файл, проверяем валидатором, **только потом** тестируем на реальных устройствах. Иначе придётся ждать сутки или переустанавливать приложение.
- **Не использовать .json для AASA.** Файл `apple-app-site-association` — без расширения. Это требование Apple. Для Android — наоборот, расширение `.json` обязательно.
- **CDN-кеширование.** Если перед сервером стоит CloudFlare/CloudFront — убедиться, что они тоже отдают `Content-Type: application/json`, не модифицируют тело и не добавляют редиректы. Для безопасности рекомендуем `Cache-Control: public, max-age=3600`.
- **Редиректы.** Любые 301/302 (включая `http → https` или `ucmatrix.org → www.ucmatrix.org`) ломают валидацию. Файл должен отдаваться напрямую по тому URL, который вы указали Apple/Google.

---

## Связь iOS / Android разработки

После того как файлы развёрнуты:

- **iOS-разработчик** (мы) — выкатывает новый билд UCMeet.Chat в TestFlight с включённым entitlement `applinks:ucmatrix.org` (уже подготовлено в ветке `feature/universal-links-ucmatrix`).
- **Android-разработчик** — добавляет в `AndroidManifest.xml` intent-filter с `android:autoVerify="true"` для `https://ucmatrix.org/...` и собирает релизный билд.

Дальше каждая команда независимо проверяет E2E на своей платформе.

---

## Smoke-test после деплоя (для финального подтверждения)

1. **Технически** — запустить `bash verify.sh` (см. Шаг 4).
2. **Со стороны пользователя** — на устройстве с установленным релизным билдом:
   - Отправить себе в Telegram ссылку вида `https://ucmatrix.org/#/!тестовая_комната:matrix.ucmeet.org`.
   - Тапнуть по ней.
   - **Ожидаемое поведение:** открывается UCMeet.Chat и переходит в указанную комнату. Если открывается Safari — что-то не так с AASA (см. логи `swcd` через Console.app или подождать сутки на случай кеша).

---

## Версия пакета

| Поле | Значение |
|---|---|
| Подготовлено | 2026-05-08 |
| Версия пакета | v1 |
| iOS App ID | `6HRG779SDK.org.ucmeet.UCMeetChat` |
| iOS Bundle ID | `org.ucmeet.UCMeetChat` |
| iOS Team ID | `6HRG779SDK` |
| Android package | `org.ucmeet.chat` |
| Android SHA-256 | `B0:B0:...:13:0E` (DEBUG, заменить после публикации в Google Play) |
| Android фрейм | `element-hq/element-x-android` (форк) |
| Android `autoVerify` | Настроен (подтверждено разработчиком 2026-05-08) |
| Контакт по iOS | Самат Мурзалиев |

При смене Bundle ID, Team ID, или релизного keystore Android — перевыпустить пакет.

