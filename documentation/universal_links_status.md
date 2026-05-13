# Universal Links / Deep Links — Project Status

> **Scope.** Status tracker for enabling Universal Links (iOS) and App Links (Android) on the `ucmatrix.org` domain so that tapping a link like `https://ucmatrix.org/#/room/...` in any other app (Telegram, Mail, Safari) opens directly inside UCMeet.Chat instead of the browser. This is the customer's "симлинки / универсальный скрипт" request.
>
> **Companion documents:**
> - Russian-language implementation plan: `documentation/deeplink-univeral-link.md`
> - Deployable artifact bundle for the customer's ops team: `documentation/universal-links-deploy/`
> - Approved engineering plan: `~/.claude/plans/the-time-has-come-tingly-dewdrop.md`
> - Decisions tracker entry: `documentation/decisions_tracker.md` (changelog 2026-05-08)
> - Daily progress: `documentation/progress_log.md` (entry 2026-05-08)

---

## TL;DR

iOS code is **complete and pushed** to `origin/feature/universal-links-ucmatrix`. The deployable bundle for the customer's ops team is **ready** but waiting on Android values before final hand-off. Nothing is in `develop` yet — PR is held until end-to-end verification on TestFlight succeeds.

---

## Overall progress

| Track | Status |
|---|---|
| iOS code (entitlement, modifier, tests, docs) | ✅ Done — merged to `develop` 2026-05-11 via PR #4 |
| Push to origin | ✅ Done |
| Russian-language implementation plan | ✅ Done — `documentation/deeplink-univeral-link.md` |
| Deploy bundle for customer ops | ✅ Done — `documentation/universal-links-deploy/` (5 files) |
| Zip bundle for delivery | ✅ Done — `~/Desktop/universal-links-deploy.zip` |
| Russian message to Android dev | ✅ Sent |
| Android dev replies with package + SHA-256 | ✅ Received 2026-05-08 (DEBUG fingerprint) |
| `assetlinks.json` filled with real values | ✅ Done (DEBUG-only, see §"Android post-Play follow-up") |
| Customer ops deploys AASA + assetlinks | ✅ **DONE 2026-05-12.** Both files at `https://ucmatrix.org/.well-known/`, served by nginx 1.24.0, HTTP/2 200, `Content-Type: application/json`, no redirects. AASA contains `appIDs: ["6HRG779SDK.org.ucmeet.UCMeetChat"]` + path matcher `"/": "/*"`. assetlinks contains `package_name: "org.ucmeet.chat"` + DEBUG SHA-256. `verify.sh` ran by customer ops with all checks passing; independently re-verified via `curl` 2026-05-13. |
| TestFlight build with new entitlement | ✅ **1.0.2 build 1 uploaded 2026-05-11** (Apple processing) |
| Install TestFlight build on test device | 🟢 **READY** — AASA is now live, safe to install. |
| End-to-end test (tap link → app opens room) | 🟢 **UNBLOCKED** — pending TestFlight install + tap test from another app (Telegram, Notes, Mail) |
| PR `feature/universal-links-ucmatrix` → `develop` | ✅ Merged 2026-05-11 (PR #4) |

---

## What is already done (iOS code)

Branch: `feature/universal-links-ucmatrix` on `origin`.

| Commit | Files | Purpose |
|---|---|---|
| `2a43111c4` | `ElementX/SupportingFiles/target.yml`, `ElementX/SupportingFiles/ElementX.entitlements` | Re-added `com.apple.developer.associated-domains: applinks:ucmatrix.org` (previously removed when matrix.to AASA didn't list our bundle ID) |
| `bd329b419` | `ElementX/Sources/Application/Application.swift` | Added `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` modifier that funnels `userActivity.webpageURL` through the existing `openURL(_:isExternalURL:)` helper |
| `3f59c3e33` | `UnitTests/Sources/AppRouteURLParserTests.swift` | Two new tests: `testUCMatrixUserURL`, `testUCMatrixRoomIdentifierURL` — all 10 parser tests pass |
| `d6f51f15a` | `CLAUDE.md`, `documentation/decisions_tracker.md`, `documentation/progress_log.md`, `documentation/deeplink-univeral-link.md` | Documentation updates + Russian implementation plan |
| `49999f922` | `documentation/universal-links-deploy/*` | Deployable bundle: AASA, assetlinks template, nginx snippet, RU README, verify.sh |

Total: ~6 production files, ~30 lines of net code change, 2 unit tests, ~600 lines of documentation and ops artifacts.

No new abstractions were introduced. The new code path reuses three pre-existing pieces:
- `AppCoordinator.handleDeepLink(_:isExternalURL:)` — `AppCoordinator.swift:240-302`
- `AppRouteURLParser.route(from:)` — `AppRoutes.swift:91-99`
- `UCMatrixPermalinkParser` — `AppRoutes.swift:177-189` (rewrites `ucmatrix.org` → `matrix.to` for SDK parsing)

---

## What is pending and why

### Pending #1 — Android dev reply ✅ RECEIVED 2026-05-08

**Status:** Closed. Values used in `assetlinks.json`:

| Field | Value | Notes |
|---|---|---|
| `package_name` | `org.ucmeet.chat` | Lowercase per Android convention; differs from iOS bundle |
| `sha256_cert_fingerprints[0]` | `B0:B0:51:DC:56:5C:81:2F:E1:7F:6F:3E:94:5B:4D:79:04:71:23:AB:0D:A6:12:86:76:9E:B2:94:91:97:13:0E` | **DEBUG key** — see post-Play follow-up below |
| Fork | `element-hq/element-x-android` | Same as iOS — relevant for matrix.to → ucmatrix.org parser symmetry |
| `autoVerify` | Configured | Android dev confirmed |
| Google Play App Signing | Will rewrite the key on publication — production SHA-256 will be different |

### Pending #1a — Android post-Play follow-up

**Owner:** Android developer.

**What:** After Android UCMeet.Chat is published in Google Play, send an updated `assetlinks.json` containing the **App Signing key certificate** SHA-256 from Play Console (App Signing → "App signing key certificate"). Customer ops re-deploys the file under the same URL.

**Why it matters:** Until this is done, App Links work only for builds signed with the current debug key (i.e., direct sideloads, not Google Play installs). Production users tap a link → opens in browser, not the app.

**No action on iOS side.**

### Pending #1b — Android matrix.to → ucmatrix.org parser symmetry

**Owner:** Android developer.

**What:** Confirm that the Android app parses `https://ucmatrix.org/...` permalinks (not just `matrix.to`). On iOS we added `UCMatrixPermalinkParser` (rewrites host before delegating to the SDK parser). Android's `element-x-android` fork likely needs the same treatment, otherwise even with App Links activating, the app will receive a `ucmatrix.org` URL and discard it.

**Recommended message to Android dev** (next conversation):

> Уточнение: на iOS, помимо entitlement и AASA, нам пришлось добавить в код приложения парсер, который при получении `https://ucmatrix.org/...` ссылок переписывает хост на `matrix.to` перед тем, как отдать SDK-парсеру (`UCMatrixPermalinkParser`). Иначе SDK не распознавал `ucmatrix.org` как валидный Matrix-permalink. Проверь, что у тебя на Android аналогично — если приложение парсит только `matrix.to`, то даже после активации App Links тапы по `ucmatrix.org`-ссылкам не приведут к навигации внутри приложения. Шаблон правки: интерсептор перед SDK permalink-парсером, который меняет хост `ucmatrix.org` → `matrix.to`.

### Pending #2 — Customer ops: deploy AASA + assetlinks.json on `ucmatrix.org`

**Owner:** Customer's ops/devops team (the team that maintains `ucmatrix.org`).

**Deliverable to send them:** `~/Desktop/universal-links-deploy.zip` (refreshed 2026-05-08, contains the filled `assetlinks.json`).

**What they do:** unzip, follow `README.md` inside (in Russian). Result must be:
- `https://ucmatrix.org/.well-known/apple-app-site-association` returns `200 OK` with `Content-Type: application/json`, contents include `appIDs: ["6HRG779SDK.org.ucmeet.UCMeetChat"]`.
- `https://ucmatrix.org/.well-known/assetlinks.json` returns `200 OK` with `Content-Type: application/json`, contents include `package_name: "org.ucmeet.chat"` + SHA-256.

**Confirmation:** they run `bash verify.sh` from the unzipped folder; it passes with no red errors.

**Sequencing:** zip is now ready. The post-Play `assetlinks.json` update (Pending #1a) is a one-time follow-up later — does not block this deploy.

### Pending #3 — TestFlight build (1.0.2 / build 6) and end-to-end verification

**Owner:** Saidakhror (iOS developer).

**Pre-conditions:** Pending #2 is fully complete and `verify.sh` passes.

**Steps:**
1. Bump version in `app.yml` to 1.0.2 / build 6, regenerate, archive, upload to TestFlight.
2. Wait for ASC processing.
3. On a clean test device (or after uninstalling the existing UCMeet.Chat), install the new TestFlight build. iOS fetches AASA at install — this is the moment the Universal Links association is established.
4. From Telegram (or Notes/iMessage), tap a `https://ucmatrix.org/#/room/...` link.
5. **Expected:** UCMeet.Chat opens, navigates to the room.
6. Verify all four canonical permalink shapes: room by ID, room by alias, user, event.
7. Smoke-test: OIDC login still works (separate code path; explicit regression check).
8. Document E2E results in `documentation/progress_log.md`.

**24-hour cache caveat:** if the build is installed before AASA is live, iOS caches "no AASA" for that domain on that device for up to 24 h. Either uninstall+reinstall, wait 24 h, or use a different device to retest. Avoid this by holding the install until ops confirms the file is up.

### Pending #4 — Open and merge PR

**Owner:** Saidakhror.

**Pre-conditions:** Pending #3 confirms E2E works.

**Steps:** open `feature/universal-links-ucmatrix` → `develop` PR, get any review, merge. After merge, the next regular release cycle includes Universal Links.

---

## Sequencing alternatives

No longer relevant — Android dev replied 2026-05-08, deploy package is complete.

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Customer ops serves AASA with wrong Content-Type or via redirect | Medium | `verify.sh` catches both; nginx snippet documents the requirements explicitly |
| iOS caches "no AASA" for ~24 h on a device that installed before AASA was deployed | Medium | Sequencing rules in this doc; uninstall+reinstall is documented as the recovery |
| Apple Developer Portal capability "Associated Domains" not enabled for our App ID | Low | Xcode auto-prompts on first build with new entitlement |
| Upstream sync re-introduces `matrix.to`-only assumptions | Low | Unit tests `testUCMatrixUserURL`/`testUCMatrixRoomIdentifierURL` catch the regression |
| OIDC login regresses due to new URL handling | Low | OIDC uses a separate custom-scheme path through `ASWebAuthenticationSession`; explicit smoke-test in pending #3 |
| Google Play App Signing makes Android dev's local keystore SHA-256 wrong | Medium | Russian message to Android dev explicitly asks about App Signing and instructs to use the Play-managed cert if applicable |
| CDN in front of `ucmatrix.org` modifies Content-Type | Low | nginx-snippet calls this out; ops will see it in `verify.sh` output |

---

## Russian message to Android dev (ready to send)

Copy-paste verbatim:

> Привет! Делаю на iOS-стороне Universal Links для UCMeet.Chat — чтобы тап по ссылке `https://ucmatrix.org/#/room/...` в Telegram/почте/любом мессенджере открывал нужную комнату прямо внутри приложения, а не в браузере.
>
> Заказчик попросил один общий деплой на сервере `ucmatrix.org`, который покрывает и iOS, и Android (один файл `.well-known/apple-app-site-association` + второй `.well-known/assetlinks.json`). Я готовлю единый пакет для их devops, и для Android-части мне нужны от тебя два значения:
>
> 1. **Package name** Android-приложения UCMeet.Chat (тот, который в `applicationId` build.gradle релизной сборки). Например: `org.ucmeet.UCMeetChat` — но скажи, как у тебя реально.
>
> 2. **SHA-256 fingerprint релизного keystore** (именно того, которым подписывается production-сборка для Google Play, не debug). Формат — 64 hex-пары через двоеточие, например `AB:CD:EF:01:23:...`. Команда для извлечения:
>    ```
>    keytool -list -v -keystore путь/к/release.keystore -alias твой_alias
>    ```
>    Найди в выводе строку `SHA256:` — это оно.
>
> Если у тебя несколько вариантов сборки (flavors / разные ключи для Play и для F-Droid и т.п.) — пришли все SHA-256, которые могут подписать релиз. Файл `assetlinks.json` поддерживает массив отпечатков.
>
> Дополнительно — пара уточнений, чтобы синхронизироваться:
>
> 3. На каком форке Matrix-клиента ты сейчас сидишь? `element-hq/element-android` (классический) или `element-hq/element-x-android` (новый)? Это нужно, чтобы понять, есть ли у вас уже готовая логика парсинга `matrix.to`-permalinks — мы у себя на iOS заменили её на `ucmatrix.org`, и тебе скорее всего понадобится такая же замена на стороне Android.
>
> 4. Уже ли в `AndroidManifest.xml` настроены intent-filter с `android:autoVerify="true"` для `ucmatrix.org`? Если нет — это надо будет добавить вместе с релизом, чтобы Google валидировал ассоциацию домена.
>
> 5. Опубликовано ли Android-приложение в Google Play (или планируется)? Если используется Play App Signing — пришли SHA-256 с Play Console (App Signing → "App signing key certificate"), а не локальный upload-key. Это частая путаница.
>
> Когда пришлёшь package name + SHA-256 — я добавлю их в общий пакет для заказчика и отправлю ему на деплой. Спасибо!

---

## Mocking / testing without customer infrastructure

Three layers, in order of practical value:

1. **Unit tests** (already passing) — `AppRouteURLParserTests` covers all five Matrix permalink shapes (room by ID, room alias, user, event-on-room, event-on-alias) for both `matrix.to` and `ucmatrix.org` hosts, plus `?via=` parameters and the bidirectional symmetry between `URL.replacingMatrixToHost()` (outgoing) and `UCMatrixPermalinkParser` (inbound).
2. **LLDB injection on a real device or simulator** — see the manual smoke-test checklist below. Bypasses iOS Universal Links delivery, exercises the whole route-and-navigate path.
3. **Stand-in AASA on a domain we control** — only worth it if we want to verify "tap in Telegram → app opens" without the customer's server. Cost: ~1 hour to host AASA on GitHub Pages / Cloudflare Pages, point entitlement at it temporarily, build TestFlight, test, revert. Skip unless we suspect a specific bug.

The simulator does **not** honor Universal Links AASA verification (`xcrun simctl openurl` opens in mobile Safari, doesn't route through our app). Full E2E requires a real device + a real AASA-serving domain.

---

## Manual smoke-test checklist (LLDB injection)

Use these commands to verify each canonical permalink shape navigates correctly **without** waiting for AASA deployment. Pre-condition: app is running in a debug build on a simulator or real device, user is logged in, and the test room/user exists on the homeserver.

**How to use:**
1. Run UCMeet.Chat from Xcode (Cmd-R).
2. Pause the debugger anywhere (e.g., set a breakpoint or hit Cmd-Ctrl-Y).
3. Paste the relevant command into the LLDB console (the `(lldb)` prompt at the bottom of Xcode).
4. Hit Enter, resume execution. App should navigate as described.

| Shape | LLDB command | Expected outcome |
|---|---|---|
| Room by ID | `expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/#/!roomid:matrix.ucmeet.org")!, isExternalURL: true)` | App opens the specified room |
| Room alias | `expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/#/%23general:matrix.ucmeet.org")!, isExternalURL: true)` | App resolves alias and opens the room |
| User profile | `expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/#/@alice:matrix.ucmeet.org")!, isExternalURL: true)` | App opens the user profile screen |
| Event in room | `expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/#/!roomid:matrix.ucmeet.org/$eventid")!, isExternalURL: true)` | App opens the room scrolled to that message |
| Unrecognised URL | `expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/random/garbage")!, isExternalURL: true)` | Returns `false`. Console.app should show: `Deep link not recognised, falling back to system browser: ...` |

**Substitute real IDs/aliases from the test homeserver before running.** The fictional values above won't resolve.

**Verifying logs after each invocation:** open Console.app, filter by process `UCMeet.Chat`. Expect to see one of:
- `Universal Link received: https://...` (from `Application.swift`'s `BrowsingWeb` modifier — only fires on real Universal Link delivery, not LLDB injection)
- `Deep link not recognised, falling back to system browser: ...` (when the URL doesn't match any AppRoute — proves the new diagnostic log works).

---

## Definition of done

This work is fully complete when **all** of the following are true:

- [ ] `verify.sh` against `ucmatrix.org` passes with no errors.
- [ ] A TestFlight build with `applinks:ucmatrix.org` entitlement is installed on a real device after AASA is live.
- [ ] Tapping `https://ucmatrix.org/#/room/<roomID>` in Telegram opens UCMeet.Chat to that room.
- [ ] Tapping `https://ucmatrix.org/#/<userID>` in Telegram opens that user's profile in UCMeet.Chat.
- [ ] OIDC login round-trip still works after the entitlement change.
- [ ] PR `feature/universal-links-ucmatrix` → `develop` merged.
- [ ] `documentation/decisions_tracker.md` records E2E confirmation.

---

*Last updated: 2026-05-08. Owner iOS: Самат Мурзалиев.*
