# Project Context — Element X iOS Branded Fork

## Project Type

**iOS/Swift/SwiftUI project.** Ignore all Flutter/Dart skills, agents, and commands.

### Slash Commands (`.claude/commands/`)

- `/git-commit`, `/git-push`, `/commit-push-pr` — Git workflows
- `/xcodegen-build` — Regenerate xcodeproj + build for iPhone 17 Pro simulator
- `/upstream-sync`, `/audit-branding`, `/create-checkpoint [name]`, `/rebrand-execute`, `/decision-status`

### Axiom Skills (use `axiom:ask` to auto-route)

`axiom-ios-build` (build failures), `axiom-xcode-debugging` (BUILD FAILED), `axiom-build-debugging` (SPM), `axiom-localization`, `axiom-privacy-ux`, `axiom-apple-docs`, `axiom-ios-testing`, `axiom-app-composition`, `axiom-ios-networking`, `axiom-codable`, `axiom-swift-concurrency`

---

## What This Is

Branded fork of **Element X iOS** (Matrix messenger, SwiftUI) → publish on App Store as **UCMeet.Chat**. Rebrand + reconfigure only. No new features.

**Developer:** Saidakhror Murzaliev (solo, 20h/week, AI-assisted)
**Customer:** Russian-speaking, existing Matrix infrastructure

## Current State (as of 2026-05-11)

**Live on App Store: 1.0.1.** TestFlight: 1.0.2 (build 1) uploaded 2026-05-11 — first build that includes upstream sync (SDK 26.05.06, OAuth rename, voice-only DM call, Live Location Sharing, multi-window) + Universal Links code (`applinks:ucmatrix.org` entitlement, `NSUserActivityTypeBrowsingWeb` handler). Smoke-tested on iPhone 17 Pro / iOS 26.4.1 simulator. Awaiting (a) customer ops to deploy AASA at `ucmatrix.org/.well-known/` for Universal Links E2E, (b) Apple TestFlight processing + customer test, (c) submission to App Store review.

### Configuration Applied

| Setting | Value |
|---------|-------|
| Bundle ID | `org.ucmeet.UCMeetChat` (cascaded through 22 files, registered in Apple Developer Portal) |
| App Group | `group.org.ucmeet` |
| Team ID | `6HRG779SDK` |
| Display Name | `UCMeet.Chat` |
| Homeserver | `matrix.ucmeet.org` |
| Push Gateway | `https://push.ucmeet.org` (Sygnal, `type: apns`). App uses direct APNs tokens (not Firebase) |
| Push Provider | `.apns` (switched from `.firebase` — Sygnal's GCM pushkin incompatible with APNs payload format) |
| OAuth (formerly OIDC) | Custom URL scheme `org.ucmeet.UCMeetChat:/callback` — login verified working post-sync 2026-05-11. **Important:** `oAuthConfiguration.clientURI` MUST stay hardcoded at `https://ucmeet.org` (NOT `websiteURL` = `www.ucmeet.info`) so the redirect-scheme reverse-DNS subdomain check in MAS passes. See `AppSettings.swift` comment for details — regression introduced and fixed during the 2026-05-10 sync. |
| Calls | URL scheme `org.ucmeet.call`, LiveKit via `.well-known` |
| Locales | en, en-US, ru (trimmed from 37) |
| Accent Color | Dark navy blue #003B5D (Compound design tokens overridden — all green→navy blue) |
| Xcode Signing | Resolved — customer's Apple ID in Xcode, automatic signing works |
| Firebase | Real GoogleService-Info.plist installed (project `matrix-8c24a`), APNs key uploaded |
| MapLibre | API key `iKPA4bK9zgtadTEw8neu` configured. Interactive maps work. Static map previews show "Invalid key" — free MapTiler plan doesn't include Static Maps API |
| Pusher App IDs | `org.ucmeet.UCMeetChat.ios.prod` (release) / `.ios.dev` (debug) |
| NSE Entitlement | `com.apple.developer.usernotifications.filtering` removed (requires Apple approval, not available for our bundle ID) |
| Encryption | `ITSAppUsesNonExemptEncryption = YES` in plist, encryption compliance document uploaded to ASC |
| Analytics | Disabled (PostHog, Sentry, rageshake all set to `nil`) |
| APP_NAME | `UCMeet.Chat` (was `ElementX` — fixed OIDC system dialog) |
| Permalinks | `ucmatrix.org` (replaced `matrix.to` — blocked in Russia). Outgoing links, mentions, share URLs all use `ucmatrix.org`. Incoming `ucmatrix.org` links parsed via `UCMatrixPermalinkParser` |
| Universal Links | `applinks:ucmatrix.org` in entitlements. `NSUserActivityTypeBrowsingWeb` handler in `Application.swift` routes `https://ucmatrix.org/...` URLs through `AppCoordinator.handleDeepLink`. **AASA + assetlinks.json deployed 2026-05-12** at `https://ucmatrix.org/.well-known/` (nginx 1.24.0, HTTP 200, `application/json`). Ready for E2E test on TestFlight 1.0.2. |
| Upstream | Synced with `element-hq/element-x-ios:release/26.05.0` 2026-05-10 (3 ahead of release tag, 0 behind) |

### Version 1.0.2 Build 2 Changes (2026-05-17) — pending upload

1. **Russian translation "Звонок начат" → "Звонок"** (`common_call_started` in `ru.lproj/Localizable.strings`). Workaround for an upstream Element X bug where the call-status timeline item never updates after the call ends (same on matrix.org reference client). Customer-requested. Single string changed; English left as "Call started".
2. **Home-screen badge auto-recompute** (`AppCoordinator.observeBadgeCount()`). Subscribes to `roomSummaryProvider.roomListPublisher` for the lifetime of the user session, reduces per-room `unreadNotificationsCount` into a total, writes to `UNUserNotificationCenter.setBadgeCount`. Fixes the customer-reported "badge stuck at (1)" bug — previously badge was only set by NSE on push and cleared on logout; in-app reads didn't decrement it.

### Version 1.0.2 Build 1 Changes (2026-05-11) — uploaded to TestFlight 2026-05-11

1. **Upstream sync to `release/26.05.0`** (267 commits). Customer-facing: voice/video call menu in DM rooms (the customer's "кнопка звонка" ask), Live Location Sharing graduated to permanent, multi-window iPad/Mac, iOS 26 cold-start crash fix. Internal: Matrix Rust SDK 26.03.10 → 26.05.06, OIDC → OAuth rename, Compound design tokens v7 → v10.1.1, Embedded Element Call 0.17.0 → 0.19.2, Xcode bumped to 26.4 (we run 26.4.1).
2. **Universal Links for `ucmatrix.org`** — `applinks:ucmatrix.org` entitlement + `NSUserActivityTypeBrowsingWeb` handler in `Application.swift` + diagnostic logs in `AppCoordinator.handleDeepLink`. Tap `https://ucmatrix.org/#/room/...` opens the app once customer ops deploys AASA.
3. **OAuth `clientURI` regression fix** (commit `3939e2cc5`) — reverted the `oAuthConfiguration` URI fields back to hardcoded `https://ucmeet.org`. The sync's "cleanup" to `websiteURL` broke MAS native-app policy. See `AppSettings.swift` for the explanation comment.
4. **Background modes added** — `voip` (CallKit voice-only DM call) + `location` (LLS) in `target.yml` `UIBackgroundModes`.
5. **6 customer-tested Russian translations re-applied** after upstream's translation refresh introduced different wording (звонок vs вызов, варианты vs опции, etc).

### Version 1.0.1 Build 1 Changes (2026-04-13)

1. **Permalinks: matrix.to → ucmatrix.org** — All outgoing permalinks (room shares, user profiles, mentions, event/message links, room aliases, "Copy link") now use `ucmatrix.org` instead of `matrix.to` (blocked in Russia). Added `URL.replacingMatrixToHost()` helper. Added `UCMatrixPermalinkParser` for incoming `ucmatrix.org` link handling. Files changed: URL.swift, AppRoutes.swift, JoinedRoomProxy.swift, MatrixUserShareLink.swift, RoomMemberProxyProtocol.swift, UserProfileScreenViewModel.swift, ComposerToolbarViewModel.swift, AttributedStringBuilder.swift

### Build 4 → Build 5 Changes (2026-03-27)

1. **Push: Firebase → APNs** — `pushProvider` default changed from `.firebase` to `.apns` in AppSettings.swift. App registers APNs device token directly instead of FCM token. Sygnal uses `type: apns` with .p8 key. Firebase SDK stays in project.
2. **Send button gradient** — `gradientActionStop1-4` overridden to navy blue in CompoundHook.swift (was green)
3. **4 more Russian translations** — "Sharing options", "No space selected", "Do not add to a space", "Add to space"

### Previous Build Changes (Build 2 → Build 4)

- OIDC dialog: `APP_NAME: ElementX` → `UCMeet.Chat`
- Analytics/bug reports disabled (PostHog, Sentry, rageshake all `nil`)
- MapTiler key configured, location sharing enabled
- 14 Russian translations added/fixed
- Navy blue color overrides (24 SwiftUI + 23 UIKit tokens)
- Test infrastructure: `PRODUCT_MODULE_NAME`, `TEST_HOST` fixes

### Remaining Blockers / Next Steps

1. **Universal Links E2E test** — install 1.0.2 build 1 from TestFlight on a real device (AASA is live as of 2026-05-12, so install is now safe), tap a `https://ucmatrix.org/#/room/...` link from Telegram/Mail, confirm app opens to that room.
2. **TestFlight customer test** — customer tests new build (voice/video DM call menu, branding, Russian translations).
3. **Android dev: post-Play SHA-256** — current `assetlinks.json` has Android DEBUG fingerprint. Android dev to send Play App Signing certificate SHA-256 after Google Play publication; customer ops re-deploys.
4. **Triage ~36 unknown test failures** from the post-sync test gauntlet (1016 tests / 67 unique failures; ~13 traceable to UCMeet customizations, ~18 Swift Testing async timeouts, ~36 unknown). Not blocking TestFlight but worth investigating before App Store submission.
5. **AGPL v3 licensing** — still need written confirmation from customer.
6. **CallKit (server-side)** — Element Call widget sending `m.rtc.notification` events. App-side has been ready; the new sync also adds voice-call CallKit support (`voip` background mode + `RtcCallIntent.audio` handling in NSE).

### Resolved Since Last Update

- ~~Universal Links AASA + assetlinks deploy~~ — **DONE 2026-05-12** by customer ops. Both files at `https://ucmatrix.org/.well-known/`, verified via `verify.sh` and independent `curl` check.
- ~~Voice/video call menu in DM~~ — **DONE** in 2026-05-10 sync (upstream `RoomCallControlsToolbar.swift`).
- ~~Universal Links iOS code~~ — **DONE** 2026-05-08, merged 2026-05-11 (PR #4).
- ~~Upstream sync~~ — **DONE** 2026-05-10 to `release/26.05.0` (PR #3).
- ~~OAuth callback regression from sync~~ — **FIXED** 2026-05-11 (commit `3939e2cc5`).
- ~~Push E2E testing~~ — **VERIFIED** on TestFlight build (2026-03-28)
- ~~Privacy Nutrition Labels~~ — **COMPLETED** in ASC (2026-04-03)
- ~~Review contact details~~ — **ENTERED** in ASC (2026-04-03)
- ~~Pricing~~ — **Set to Free** in ASC (2026-04-03)
- ~~Privacy policy + support URLs~~ — **ENTERED** in ASC (2026-04-03)
- ~~ucmatrix.org outgoing permalink rewrite~~ — **DONE** (2026-04-13)

### Open Items

1. **MapTiler** — customer decision on paid plan for static map previews

> See `decisions_tracker.md` for all 12 tracked decisions: 9 resolved, 1 in progress, 2 deferred.

---

## Source Project Facts

| Fact | Value |
|------|-------|
| Upstream | `element-hq/element-x-ios` (synced 2026-05-10 to `release/26.05.0`, SDK v26.05.06) |
| Architecture | Coordinator-based MVVM, SwiftUI, ~68k LOC, ~907 Swift files |
| Build system | XcodeGen (`project.yml`, `app.yml`, `target.yml`) + SPM |
| Core SDK | Matrix Rust SDK v26.05.06 (opaque binary, **cannot modify**) |
| License | AGPL v3 |
| iOS minimum | 18.0 |
| Xcode required | 26.4+ |
| Push | APNs + Firebase SDK (FCM, 14 unit tests) |
| Calls | Element Call (MatrixRTC + LiveKit) — voice/video toggle in DM toolbar (since 2026-05-10 sync) |
| Auth | OAuth (formerly OIDC, renamed upstream 2026-05) via MAS, custom-scheme callback `org.ucmeet.UCMeetChat:/callback` |

## Key Files

```
app.yml                    → Bundle ID, display name, team ID, app group
AppSettings.swift          → Homeserver, OIDC, push gateway, analytics, legal URLs, feature flags
target.yml / entitlements  → Associated domains, push, app group
Assets.xcassets            → App icon, accent color
GoogleService-Info.plist   → Firebase config
```

---

## Working Rules

- **No new features.** Rebrand + reconfigure only.
- **Do not modify Matrix Rust SDK** — opaque binary.
- **Never edit `.xcodeproj` directly** — edit YAML, then `xcodegen generate`.
- **Keep fork minimal** — every change increases upstream merge difficulty.
- Customer docs → **Russian**. Code/technical docs → **English**.
- Track decisions in `decisions_tracker.md`. Update after customer interactions.
- **Before modifying any file:** Read it first.
- **When a decision is unresolved:** Do not guess. Flag it and ask.

### Git

- Branching: `main` (releases) + `develop` (active, default) + `upstream` remote
- Tag `checkpoint/unmodified-build` at `7c96ebfca`, `checkpoint/branding-complete` at `caf1d6872`
- Commit format: imperative, concise (match upstream style)

---

## Build Environment

| Tool | Version |
|------|---------|
| Xcode | 26.2 |
| XcodeGen | 2.44.1 |
| Firebase SDK | 11.8.x |
| Simulator | iPhone 17 Pro |
| git-lfs, gh CLI | installed |

---

## Documentation Index

All docs in `documentation/` folder:

**Core:** `project_overview.md`, `tor.md`, `preliminary_assessment.md`, `decisions_tracker.md`, `change_map.md`

**Development:** `ios_proj_init.md` (15-step plan), `implementation_plan.md`, `firebase_integration.md`, `pre_rebranding_preparations.md`, `build_and_handover_guide.md`, `sprints.md`, `dev_plan.md`, `overall_implementation_progress.md`

**Audits:** `oidc_audit.md`, `branding_audit.md`, `nse_audit.md`, `share_extension_audit.md`, `hardcoded_identifiers_inventory.md`, `element_call_audit.md`, `privacy_manifest_audit.md`, `upstream_sync_report.md`

**App Store:** `app_store_prep_templates.md`, `appstore_connect_guide.md`

**Customer:** `customer_pre_dev_briefing_ru.md`, `customer_questionnaire_init_stage.md`

**Progress:** `progress_log.md` (detailed daily log)

---

## Phase Progression

- [x] Phase 0: Planning
- [x] Phase 1: Project Setup (fork, build, audit, branding, config, OIDC, calls, localization)
- [ ] Phase 2: Licensing (AGPL confirmation pending)
- [x] Phase 3: Branding (complete — UCMeet.Chat, logos, accent color)
- [x] Phase 4: Server Config + OIDC (complete — login working)
- [~] Phase 5: Push Notifications (code done, Firebase configured, APNs key uploaded. E2E blocked on customer Sygnal config)
- [x] Phase 6: Calls (complete — LiveKit confirmed)
- [ ] Phase 7: Testing & QA
- [ ] Phase 8: App Store Prep
- [ ] Phase 9: Release
- [ ] Phase 10: Documentation & Handover

### Sprint Status

| Sprint | Status | Notes |
|--------|--------|-------|
| 1: Environment Setup & Fork | **DONE** | |
| 2: Branding & Basic Functionality | **DONE** | MapLibre interactive maps work, static previews need MapTiler permission |
| 3: Push + OIDC + Associated Domains | **DONE** | APNs via Sygnal working. Push E2E verified on TestFlight. CallKit deferred (Element Call widget issue) |
| 4: Calls & UCMeet Call | **DONE** | |
| 5: Finalization & Release Prep | **DONE** | NSE entitlement fix, upstream sync, version set to 1.0.0 (Build 2) |
| 6: TestFlight & Publication | **IN PROGRESS** | ASC listing complete except screenshots. Privacy Labels done. Review notes updated. Pricing set. Waiting: screenshots + AGPL confirmation |

### Summary Metrics

| Metric | Value |
|--------|-------|
| Plan completion | ~99% code, waiting for screenshots + AGPL confirmation |
| Hours invested | ~104h of ~120h budget |
| Hours remaining | ~6–10h (Build 5 upload, AGPL link, submission, review response) |
| Decisions resolved | 9/12 |
| Unit tests | Post-sync 2026-05-10: 1016 run, 67 unique failures (~13 traceable to UCMeet customizations like ucmatrix.org permalinks, matrix.ucmeet.org homeserver, analytics nil; ~18 Swift Testing async timeouts; ~36 to triage). Baseline pre-sync: 962/899/63. AppRouteURLParserTests: all 16 ✅. |
| Build | 1.0.2 (build 1) on TestFlight 2026-05-11. **1.0.2 (build 2) ready for archive 2026-05-17** with badge-recompute fix + RU call-status translation. Live App Store version: 1.0.1. |
| User-visible Element branding | **0** |
| Upstream divergence | 0 ahead, 0 behind `release/26.05.0` (synced 2026-05-10). Branch `chore/upstream-sync-2026-05` ahead of `develop` by the 2 sync commits until merged. |

---

*Last updated: 2026-05-11 (TestFlight 1.0.2 build 1). See `documentation/progress_log.md` for detailed daily log.*
