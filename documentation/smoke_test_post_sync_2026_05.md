# Manual Smoke Test — post upstream-sync + Universal Links (2026-05-11)

> **Purpose:** Verify the merged develop branch (PR #3 sync + PR #4 Universal Links) before bumping `MARKETING_VERSION` and uploading to TestFlight.
>
> **Estimated time:** 30–45 minutes.
>
> **What you need:**
> - Xcode 26.4.1 open with the project
> - iPhone 17 Pro / iOS 26.4.1 simulator (you already have this)
> - A test account on `matrix.ucmeet.org` (existing one is fine)
> - Console.app open in parallel for log inspection
>
> **If anything fails:** stop, capture a screenshot or paste the log line, and we'll triage. Don't proceed to TestFlight upload until all critical-path tests pass.

---

## Setup (5 min)

### 1. Pull latest develop locally

```bash
cd /Users/macbookpro/Documents/private/ucmeet-chat-ios
git checkout develop
git pull --ff-only origin develop
```

Verify you're on `develop` and at commit `2db70bd7b` or later:

```bash
git log --oneline -1
```

### 2. Regenerate the Xcode project

```bash
xcodegen generate
```

(Should be a no-op if everything is in sync, but always safe to run.)

### 3. Open Xcode

```bash
open ElementX.xcodeproj
```

### 4. Pick simulator and run

In the Xcode toolbar:
- Scheme: **ElementX**
- Destination: **iPhone 17 Pro · iOS 26.4.1**
- Press **Cmd-R** (Run)

Wait for the build (first build after fresh checkout will take ~3–5 min for SPM resolution and full compile).

### 5. Open Console.app in parallel

- Launch `Console.app` (Spotlight → "Console")
- Left sidebar → select your simulator (under "Devices")
- Search bar (top right): filter by `process:UCMeet.Chat OR subsystem:io.element OR subsystem:org.ucmeet`
- Keep this window visible — you'll glance at it during each test

---

## Critical-path tests (must pass before TestFlight)

### ✅ Test 1 — App launches without crash (iOS 26 keyWindow fix)

**Why:** Upstream commit `4188a10ea` fixes a cold-start crash on iOS 26 when the scene's keyWindow is nil. We want to verify it works in our build.

**Steps:**
1. App launches automatically after Cmd-R.
2. Watch the simulator screen.

**Expected:** Splash screen shows, then either the login screen (if you haven't logged in yet) or the home/room list (if you have a saved session).

**Fail signals:**
- Black screen for >5 seconds
- App crashes to home screen
- Console shows a crash log mentioning `keyWindow` or `SceneDelegate`

---

### ✅ Test 2 — Branding intact

**Why:** All our customer-required visual customizations should survive the sync.

**Steps:**
1. Look at the simulator app icon on the home screen.
2. Open the app → look at the title bar / navigation bar color.
3. Tap any button or interactive element to see the accent color.

**Expected:**
- App icon: UCMeet logo (3D blue/navy square)
- App display name under icon: **UCMeet.Chat**
- Title bar/accents: **navy blue (#003B5D)**, NOT green
- Send-message button: navy blue gradient
- Toggles, links, badges: navy blue

**Fail signals:**
- Green tints anywhere in the UI (would mean Compound v10.1.1 broke our color overrides)
- "ElementX" text anywhere user-facing
- Different app icon

---

### ✅ Test 3 — OAuth/OIDC login round-trip

**Why:** This was the highest-risk area of the sync (OIDC → OAuth rename, 4 PRs touched it). We kept our custom-scheme callback `org.ucmeet.UCMeetChat:/callback`. Need to verify it still completes the round-trip.

**Steps:**
1. If already logged in, sign out: tap profile → Settings → Sign out → confirm.
2. From the welcome/login screen, tap **"Sign in"** (or equivalent).
3. Enter homeserver: `matrix.ucmeet.org` (it may be pre-filled).
4. Tap Continue.
5. ASWebAuthenticationSession opens — login with your test account credentials.
6. After approving, the system browser should redirect to `org.ucmeet.UCMeetChat:/callback?...`.
7. App should re-foreground and complete the login.

**Expected:**
- Login completes within 15 seconds after entering credentials
- App lands on the home screen with your room list visible
- Console.app shows no `error:` lines about OAuth callback parsing
- Console may show a new `MXLog.info` line referencing the callback URL (from upstream's #5504 route logs)

**Fail signals:**
- After credential entry, app stays in browser instead of returning
- App returns but shows error
- Console shows "Deep link not recognised" referencing the callback URL (would mean the new `OAuthCallbackURLParser` isn't matching our redirect)

**If it fails:** Most likely cause would be `appSettings.oAuthRedirectURL` not matching what MAS sends. Check `ElementX/Sources/Application/Settings/AppSettings.swift` line ~275 — should be `URL(string: "org.ucmeet.UCMeetChat:/callback")`.

---

### ✅ Test 4 — **Voice/video call menu in DM rooms (THE customer-headline feature)**

**Why:** This is exactly what the customer asked for in their message about "кнопка звонка с новой сборки element-ios". New file `ElementX/Sources/Screens/RoomScreen/View/RoomCallControlsToolbar.swift` adds a menu in 1:1 rooms.

**Steps:**
1. From the home screen, find an **existing 1:1 DM** with another user, OR start a new chat with a user.
   - To start a new chat: tap the compose/new-message button → search for a user by `@handle:matrix.ucmeet.org`.
2. Open that DM room (a chat where there are exactly 2 people).
3. Look at the **top-right toolbar** of the room screen.

**Expected:**
- Toolbar shows a **single phone-icon button** (compound `voiceCallSolid` glyph).
- **Tap it** — a menu pops up with two options:
  - 🎤 **Start voice call** (or "Начать голосовой звонок" in Russian — see Test 7)
  - 📹 **Start video call** (or "Начать видеозвонок")
- Tap **"Start voice call"** → Element Call screen opens in **audio-only mode** (no video preview).

**Fail signals:**
- Toolbar shows only a video-call button (no menu) → either you're in a group room, not a DM, OR the new `RoomCallControlsToolbar` didn't make it through the merge
- Tapping "Start voice call" launches a video call instead → the `voiceOnly: true` flag isn't propagating through `UserSessionFlowCoordinator → ElementCallConfiguration`

**Server-side caveat:** The voice-call menu will appear regardless, but the **other party** receiving the voice call will only correctly see "incoming voice call" if your customer's Element Call backend on `call.ucmeet.org` is on a recent enough version that supports `m.rtc.notification` with `call_intent: audio`. Worth confirming with customer ops before TestFlight.

---

### ✅ Test 5 — Group room: single video-call button (no menu)

**Why:** The new toolbar should show a menu **only** in DMs. Group rooms keep the old behavior.

**Steps:**
1. From home screen, find a room with 3+ people (any group chat, including a public room).
2. Open it.
3. Look at the toolbar.

**Expected:**
- Single **video-call button** (compound `videoCallSolid` glyph), no menu.
- Tapping it launches a video call directly.

**Fail signals:**
- Menu appears in group rooms (regression — `viewState.isDirectOneToOneRoom` is misfiring)

---

### ✅ Test 6 — Permalink generation still uses `ucmatrix.org`

**Why:** Our customer-required `matrix.to → ucmatrix.org` rewrite (via `URL.replacingMatrixToHost()`) is critical for Russia (matrix.to is blocked there). We need to verify the sync didn't introduce new `matrix.to` callsites.

**Steps:**
1. Open any room.
2. Tap the room name (top of screen) → opens room details.
3. Tap **"Share"** (or "Copy link" — varies by version).
4. The share sheet appears with a URL.

**Expected:**
- URL starts with `https://ucmatrix.org/`, **NOT** `https://matrix.to/`
- Same for: room aliases, user profile share links, message permalinks ("Copy link" on a specific message)

**Repeat for:**
- A user profile: tap a user's avatar → tap their handle → Share → check URL
- A specific message: long-press a message → "Copy link" → paste somewhere visible to see the URL

**Fail signals:**
- Any link starts with `matrix.to` → upstream introduced a new permalink generator that bypassed our `replacingMatrixToHost()` call. Grep the codebase: `grep -rn "matrixToUser\|matrixToRoom\|matrixToEvent" ElementX/Sources/` and verify each callsite has `.replacingMatrixToHost()` chained.

---

### ✅ Test 7 — Russian locale + customer-tested translations

**Why:** We re-applied 6 customer-tested Russian translations after upstream's translation refresh introduced different wording. Verify they show.

**Steps:**
1. Open simulator → Settings app (the iOS Settings, not UCMeet's).
2. **General → Language & Region → iPhone Language → Русский**.
3. Confirm — simulator restarts in Russian.
4. Re-open UCMeet.Chat.
5. Navigate around and verify the following strings appear (look for them in the relevant screens):

| Where to look | Expected Russian text |
|---|---|
| In a DM, tap the call menu | **"Начать голосовой звонок"** (NOT "Начать голосовой вызов") |
| Send a Live Location share | **"Поделиться геопозицией"** (NOT "Поделиться местоположением в реальном времени") |
| Location sharing options sheet | **"Параметры отправки"** (NOT "Параметры общего доступа") |
| Long-press attachment / "More options" menu | **"Другие варианты"** (NOT "Другие опции") |
| Receive an incoming call notification | **"📞 Входящий звонок"** (NOT "📞 Входящий вызов") |
| Live location timestamp on map | **"Отправлено [время]"** (NOT "Поделился [время]") |

**Fail signals:**
- Any of these strings shows the upstream wording instead → the post-sync re-application of translations got reverted somehow. Check `ElementX/Resources/Localizations/ru.lproj/Localizable.strings`.

**After test:** switch back to English if you want.

---

### ✅ Test 8 — Send a message

**Why:** Smoke test for general timeline / send pipeline. Ensures SDK 26.05.06 didn't break basic functionality.

**Steps:**
1. Open any room you have access to.
2. Tap the composer at the bottom.
3. Type "test from post-sync build" or similar.
4. Tap send.

**Expected:**
- Message appears in the timeline within 1–2 seconds
- Read receipt indicator updates normally
- No console errors about send queue

**Fail signals:**
- Message appears as "Failed to send" → SDK regression, check Console for the error

---

## Universal Links tests (limited without AASA)

### ⚠️ Test 9 — Universal Links inbound (LLDB injection, since AASA not yet deployed)

**Why:** The `applinks:ucmatrix.org` entitlement is now in the build, but iOS only activates Universal Links once it successfully fetches the AASA file from `https://ucmatrix.org/.well-known/apple-app-site-association`. That file isn't deployed yet (waiting on customer ops). So for now we test the **routing logic** by injecting a URL via LLDB — bypassing the OS-level Universal Links delivery but exercising every line of code that runs after.

**Steps:**
1. With the app running on the simulator from Xcode (Cmd-R), set a breakpoint anywhere (or pause via Cmd-Ctrl-Y).
2. In Xcode's bottom panel, find the **LLDB console** (the `(lldb)` prompt).
3. Paste this command (substitute a real room ID from your test homeserver):

```
expression -l swift -- ((UIApplication.shared.delegate as! AppDelegate).appCoordinator as! AppCoordinator).handleDeepLink(URL(string: "https://ucmatrix.org/#/!realRoomId:matrix.ucmeet.org")!, isExternalURL: true)
```

4. Hit Enter, then resume execution (Cmd-Ctrl-Y or the play button).

**Expected:**
- App navigates to the room (assuming you're a member of it)
- Console.app shows: `Universal Link received: https://ucmatrix.org/...` (the new `MXLog.info` from our universal-links work)

**Repeat for:**
- User: `https://ucmatrix.org/#/@alice:matrix.ucmeet.org`
- Room alias: `https://ucmatrix.org/#/%23general:matrix.ucmeet.org`
- Unknown URL (negative test): `https://ucmatrix.org/random/garbage`
  - **Expected:** Console shows `Deep link not recognised, falling back to system browser: https://ucmatrix.org/random/garbage` (the new diagnostic log we added). Method returns `false`.

**Fail signals:**
- App doesn't navigate → routing through `appRouteURLParser` is broken
- No `MXLog.info` line in Console → either the log call isn't compiling, or the function isn't being hit

**Full E2E (deferred until AASA deploys):**
- Once customer ops deploys AASA + the assetlinks.json
- Install the next TestFlight build on a real device
- Send yourself a `https://ucmatrix.org/#/room/...` link in Telegram
- Tap it → app should open directly to the room

---

## Optional — non-blocking but nice to verify

### ⚠️ Test 10 — New background modes don't crash on cold start

**Why:** We added `voip` and `location` to `UIBackgroundModes` for voice-only DM call CallKit + LLS. iOS sometimes complains at startup if a background mode is declared but the app hasn't requested the corresponding permission/capability.

**Steps:**
1. Hard-quit the app from the simulator (swipe up + swipe up on the app card).
2. Re-launch from the home screen icon.

**Expected:**
- Cold start completes normally, no hang/crash
- No iOS-level alert about "this app is using location in the background" or similar (those should only appear when location is actually requested)

**Fail signals:**
- Crash → check Console for the panic; we may need to remove a background mode

---

### ⚠️ Test 11 — Multi-window (iPad only — skip if no iPad simulator)

If you have an iPad simulator and want to verify upstream's multi-window work:
1. Long-press a room → "Open in new window"
2. Verify a second window opens with that room
3. Switch between them via App Switcher (Cmd-Tab in the simulator)

This isn't customer-required — just a sanity check that our `target.yml` `UIApplicationSupportsMultipleScenes: true` change is wired through.

---

## After smoke test passes

If everything ✅:

1. **Bump version numbers** in `project.yml`:
   - `MARKETING_VERSION: 1.0.1` → `1.0.2` (or `1.1.0` to signal "big update including new features")
   - `CURRENT_PROJECT_VERSION: 1` → `2`
2. `xcodegen generate`
3. In Xcode: **Product → Archive**, then upload to TestFlight via Organizer.
4. **Don't install the new TestFlight build on a test device until customer ops confirms AASA is live** at `https://ucmatrix.org/.well-known/apple-app-site-association` — iOS caches "no AASA" for 24h on first failed fetch.
5. Send the deployment package to customer ops: `~/Desktop/universal-links-deploy.zip`.
6. Notify the Android dev about the post-Play `assetlinks.json` follow-up (per `documentation/universal_links_status.md` §"Pending #1a").

## If something fails

1. Capture screenshot (`Cmd-S` in the simulator) and/or paste the relevant Console log line.
2. Note exactly which test step.
3. Don't push or upload anything yet.
4. We can revert the offending PR via `git revert -m 1 <merge-commit>` on develop and push, which closes both PRs cleanly without history rewrite.

The merge commits to revert if needed:
- Universal Links: `2db70bd7b`
- Upstream sync: `77f4f88ab`

Reverting in either order is fine, but if you revert the sync, the Universal Links work likely won't compile anymore (it depends on post-sync types like `OAuthConfiguration`).

---

*Prepared 2026-05-11. Owner: Самат Мурзалиев.*
