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

## Шаг 3. Конфигурация веб-сервера (nginx)

Если используется nginx — см. `nginx-snippet.conf`. Главные пункты:

- Файлы должны отдаваться с `Content-Type: application/json`.
- Никаких редиректов с `/.well-known/...` (часто `.well-known/` уже перехватывается ACME / Let's Encrypt — наши location-блоки должны быть определены **после** общего блока или в отдельном server-блоке).
- Для Apache, Caddy, S3+CloudFront и т.д. — те же требования; конкретный синтаксис конфига отличается.

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

*Подготовлено: 2026-05-08. Контактное лицо по iOS: Самат Мурзалиев.*
