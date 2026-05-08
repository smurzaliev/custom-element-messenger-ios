# План реализации Universal Links / Deep Links для UCMeet.Chat

> **Контекст.** Заказчик использует слово «симлинки», но речь идёт о **Universal Links (iOS)** и **App Links (Android)** — механизме, при котором тап по ссылке `https://ucmatrix.org/...` (в Telegram, Safari, почте и т.д.) открывает её прямо внутри приложения UCMeet.Chat, а не в браузере.
>
> На сегодня (2026-05-06) приложение **формирует** ссылки `ucmatrix.org` и **умеет их парсить внутри** (`UCMatrixPermalinkParser`), но iOS не передаёт эти ссылки в приложение, потому что:
> 1. В entitlements **отсутствует** `com.apple.developer.associated-domains` (намеренно удалён в `ElementX/SupportingFiles/target.yml:114`).
> 2. На сервере `ucmatrix.org` **не размещён** файл `apple-app-site-association` (AASA).
>
> Без обоих условий Universal Links не работают — ни одно из них не имеет смысла без другого.

---

## 1. Что нужно от заказчика (бэкенд / `ucmatrix.org`)

Заказчик должен разместить два статических JSON-файла на домене `ucmatrix.org`. Это и есть «универсальный скрипт», о котором идёт речь в переписке.

### 1.1. Файл для iOS — Apple App Site Association (AASA)

**URL:** `https://ucmatrix.org/.well-known/apple-app-site-association`

**Содержимое (передать заказчику как есть):**

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["6HRG779SDK.org.ucmeet.UCMeetChat"],
        "components": [
          {
            "/": "/*",
            "comment": "Все пути на ucmatrix.org обрабатывает приложение"
          }
        ]
      }
    ]
  }
}
```

**Жёсткие требования к хостингу (без них Apple молча отбросит файл):**

| Требование | Значение |
|---|---|
| Протокол | Только `https://` (TLS-сертификат должен быть валиден) |
| Путь | Точно `/.well-known/apple-app-site-association` (без `.json` в имени!) |
| `Content-Type` | `application/json` |
| HTTP-статус | `200 OK` (никаких 301/302 редиректов) |
| Размер | < 128 KB |
| Подпись | Не требуется на iOS 9+ (раньше требовался CMS-подписанный файл) |

### 1.2. Файл для Android — Digital Asset Links

**URL:** `https://ucmatrix.org/.well-known/assetlinks.json`

**Шаблон (заказчик / Android-разработчик заполняют после генерации релизного ключа Android-приложения):**

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "ЗАМЕНИТЬ_НА_PACKAGE_ANDROID",
      "sha256_cert_fingerprints": [
        "ЗАМЕНИТЬ_НА_SHA256_РЕЛИЗНОГО_КЛЮЧА"
      ]
    }
  }
]
```

> Android-разработчик пришлёт `package_name` и SHA-256 fingerprint релизного keystore. iOS-команда (мы) к этому файлу отношения не имеет, но включаем его в общий «универсальный скрипт» для удобства заказчика.

### 1.3. Проверка после деплоя

Заказчик должен подтвердить, что оба URL отвечают `200 OK` с правильным `Content-Type`:

```bash
curl -I https://ucmatrix.org/.well-known/apple-app-site-association
curl -I https://ucmatrix.org/.well-known/assetlinks.json
```

Дополнительно проверяем валидатором Apple: `https://branch.io/resources/aasa-validator/` (вводим домен, выбираем production).

---

## 2. Что нужно сделать на стороне iOS (наша часть)

### 2.1. Добавить associated-domains в entitlements

**Файл:** `ElementX/SupportingFiles/target.yml`

В блоке `entitlements.properties` (строки ~110-121) добавить:

```yaml
    entitlements:
      path: ElementX.entitlements
      properties:
        aps-environment: development
        com.apple.developer.associated-domains:
        - applinks:ucmatrix.org
        com.apple.developer.usernotifications.communication: true
        # ... остальное без изменений
```

> Комментарий «Associated domains removed» в строке 114 — удалить.

### 2.2. Регенерация xcodeproj

```bash
xcodegen generate
```

Проверить, что в Apple Developer Portal у App ID `org.ucmeet.UCMeetChat` включён capability **Associated Domains** (если нет — Xcode при автоподписи попросит включить, нужно подтвердить).

### 2.3. Проверить обработку входящих Universal Links в коде

iOS доставляет Universal Link через `NSUserActivity` с типом `NSUserActivityTypeBrowsingWeb` в:
- `application(_:continue:restorationHandler:)` (UIKit AppDelegate),
- или `scene(_:continue:)` (SwiftUI/SceneDelegate),
- или `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` модификатор (SwiftUI).

В кодовой базе ElementX обработка маршрутов уже централизована в `ElementX/Sources/Application/Navigation/AppRoutes.swift`. Нужно убедиться, что:

1. Точка входа Scene/AppDelegate перехватывает `NSUserActivity` с `webpageURL` и передаёт его в `AppRoutes` / `URLHandler`.
2. `UCMatrixPermalinkParser` корректно парсит реальные URL вида:
   - `https://ucmatrix.org/#/room/!roomId:server.org`
   - `https://ucmatrix.org/#/user/@user:server.org`
   - `https://ucmatrix.org/#/event/!roomId:server.org/$eventId`
3. Если приложение не запущено — после холодного старта пользователя ведёт на нужную комнату, а не на главный экран.

> **Подводный камень.** Matrix-permalinks хранят данные во **фрагменте** URL (`#/...`), а не в пути. Apple AASA-матчер `"/": "/*"` — про **путь**, а фрагмент придёт в приложение независимо. Поэтому шаблон `"/*"` подходит. Но это нужно проверить на реальной ссылке.

### 2.4. Тестирование

Universal Links **не работают** при установке через Xcode-Run в чистом виде на некоторых конфигурациях. Тестировать обязательно через **TestFlight-сборку** или Ad-Hoc:

1. Установить TestFlight-сборку с новым entitlement.
2. После установки система iOS подтянет AASA с `ucmatrix.org` (это происходит автоматически в фоне).
3. Отправить ссылку `https://ucmatrix.org/#/room/...` в Telegram/Notes/iMessage самому себе.
4. Тап по ссылке должен открыть UCMeet.Chat и перейти в комнату.
5. Если открывается Safari — диагностика: `Settings → Developer → Universal Links → ucmatrix.org` (показывает, какие домены ассоциированы с приложением).

Дополнительная диагностика на устройстве через Console.app:
```
process:swcd
```
покажет ошибки загрузки AASA (типичные: `not signed`, `404`, `wrong content-type`).

### 2.5. Обновить документацию

- `documentation/decisions_tracker.md` — закрыть пункт по симлинкам.
- `CLAUDE.md` — обновить таблицу конфигурации (добавить строку Associated Domains).
- `documentation/progress_log.md` — записать день внедрения.

---

## 3. Последовательность работ и зависимости

```
[Заказчик деплоит AASA + assetlinks.json]
              │
              ▼
[Мы добавляем applinks:ucmatrix.org в entitlements]
              │
              ▼
[xcodegen generate → пересборка]
              │
              ▼
[Релиз новой TestFlight-сборки (1.0.2 / build 6)]
              │
              ▼
[E2E тест: ссылка из Telegram → открывается в UCMeet.Chat]
              │
              ├─ Работает → закрываем пункт, отправляем в App Store
              └─ Не работает → диагностика swcd / валидатор AASA
```

**Критическая зависимость:** AASA-файл должен быть на сервере **до** публикации новой сборки в TestFlight, иначе iOS закеширует «нет домена» на сутки и Universal Links не активируются до следующей переустановки приложения.

---

## 4. Оценка трудозатрат (iOS-разработчик)

> Это оценка **только iOS-части**. Время заказчика на деплой AASA не входит. Время Android-разработчика не входит.

| Этап | Время | Комментарий |
|---|---|---|
| 4.1. Подготовка AASA-шаблона + инструкций для заказчика | **1 ч** | JSON, требования к хостингу, curl-проверки |
| 4.2. Изменение `target.yml` + регенерация проекта | **0.5 ч** | Минимальная правка |
| 4.3. Проверка/доработка обработки `NSUserActivity` в `SceneDelegate` / `AppRoutes` | **1–2 ч** | Возможно, уже работает (есть `UCMatrixPermalinkParser`); нужно прочитать сцены и убедиться, что `webpageURL` доходит до парсера |
| 4.4. Локальная проверка через Safari Dev Tools + симулятор | **0.5 ч** | Базовый smoke-test |
| 4.5. Сборка и заливка нового билда в TestFlight | **0.5 ч** | Стандартная процедура |
| 4.6. E2E-тестирование на устройстве (после деплоя AASA заказчиком) | **1–2 ч** | Часто 1–2 итерации из-за MIME-type / редиректов на сервере заказчика |
| 4.7. Помощь заказчику с диагностикой AASA (если не подтянется) | **1–2 ч** | swcd-логи, валидатор Apple, советы по nginx |
| 4.8. Обновление документации + закрытие пункта в трекере | **0.5 ч** | |
| **ИТОГО** | **6–9 часов** | Распределено на 1–2 календарные недели |

### Что может растянуть сроки

- Сервер `ucmatrix.org` отдаёт AASA с редиректом или неправильным `Content-Type` → 1–2 итерации диагностики (+1–2 ч).
- iOS не подхватывает AASA из-за CDN-кеша → ждать до 24 ч между попытками.
- Apple Developer Portal не имеет включённого capability Associated Domains для App ID → +15 минут на включение.
- Заказчик отдаст AASA не сразу → календарный простой, но не наше время.

### Что НЕ требуется

- Никаких изменений в Matrix Rust SDK (опаковый бинарник).
- Никаких изменений в OIDC — он использует **отдельную** custom URL scheme `org.ucmeet.UCMeetChat:/callback`, она не пересекается с Universal Links.
- Никаких изменений в push-уведомлениях.

---

## 5. Резюме для заказчика (русский, для отправки в чат)

> Универсальные ссылки (то, что в переписке называется «симлинки») требуют двух частей:
>
> 1. **На сервере `ucmatrix.org`** — разместить два JSON-файла по фиксированным путям:
>    - `https://ucmatrix.org/.well-known/apple-app-site-association` (для iOS),
>    - `https://ucmatrix.org/.well-known/assetlinks.json` (для Android).
>
>    Содержимое и требования к хостингу мы пришлём отдельным сообщением.
>
> 2. **В приложениях** — добавить декларацию домена `ucmatrix.org` в entitlements iOS и intent-filter Android. Эту часть берём на себя.
>
> С нашей стороны (iOS) — около **6–9 часов работы**, включая E2E-тестирование. Можем приступить сразу после того, как ваш сервер начнёт отдавать AASA-файл (мы подготовим его шаблон в течение часа). Один и тот же серверный конфиг работает и для iOS, и для Android — это и есть «универсальный скрипт».

---

*Подготовлено: 2026-05-06. Owner iOS: Самат Мурзалиев.*
