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
| `apple-app-site-association` | Манифест для iOS (готов, не требует правки) | Залить как есть |
| `assetlinks.json.template` | Шаблон манифеста для Android | Заменить два значения, переименовать в `assetlinks.json`, залить |
| `nginx-snippet.conf` | Пример конфигурации nginx | Адаптировать под вашу конфигурацию |
| `verify.sh` | Скрипт проверки после деплоя | Запустить, убедиться что всё ОК |
| `README.md` | Этот файл | — |

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

## Шаг 2. Заполнить и развернуть Android-файл

**Целевой URL:** `https://ucmatrix.org/.well-known/assetlinks.json`

1. Скопировать `assetlinks.json.template` → `assetlinks.json`.
2. Заменить два значения, которые пришлёт Android-разработчик UCMeet.Chat:
   - `REPLACE_WITH_ANDROID_PACKAGE_NAME` → package name Android-приложения, например `org.ucmeet.UCMeetChat`.
   - `REPLACE_WITH_RELEASE_KEYSTORE_SHA256` → SHA-256 fingerprint **релизного** keystore (не debug). Формат: `AB:CD:EF:01:23:...` (64 hex-пары через двоеточие).
3. Залить итоговый `assetlinks.json` на сервер.

**Требования Google такие же, как у Apple** (HTTPS, 200 OK, `application/json`, без редиректов). Расширение `.json` здесь обязательно.

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
| Android package | `<заполняется Android-разработчиком>` |
| Android SHA-256 | `<заполняется Android-разработчиком>` |
| Контакт по iOS | Самат Мурзалиев |

При смене Bundle ID, Team ID, или релизного keystore Android — перевыпустить пакет.

