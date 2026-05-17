# Plan: Triage and Fix 67 Post-Sync Unit Test Failures

> **Status:** Plan only. No code changes yet.
> **Author:** iOS team (Saidakhror).
> **Date:** 2026-05-17.
> **Trigger:** CI on `develop` reports red on every push since the 2026-05-10 sync. Initial cause was 2 SwiftFormat violations (fixed in `e9a4fa79c` today); next CI run is expected to surface the 67 unit-test failures that the lint gate was masking. This plan eliminates them.
>
> **Goal:** Get `xcodebuild test UnitTests` to 0 failures (or N documented + skipped) so CI on `develop` and PR-to-`develop` becomes a meaningful quality signal again.

---

## Context

After the 2026-05-10 sync to `release/26.05.0` (PR #3), the UnitTests scheme reports **1016 tests run / 67 unique failures** locally. Pre-sync baseline was 962 / 899 / 63. So the sync added 54 tests upstream and ~4 new failures net (but with very different distribution of which tests fail).

Failures cluster cleanly into 5 categories:

| # | Category | Suite examples | Count | Root cause |
|---|---|---|---|---|
| **A** | UCMeet customization assertions | AttributedStringBuilderTests, ComposerToolbarViewModelTests, AnalyticsTests, AuthenticationServiceTests, RoomEventStringBuilderTests | ~38 | Upstream tests assert defaults we deliberately changed (matrix.to/matrix.org/non-nil analytics). Tests need updating, behaviour is correct. |
| **B** | Swift Testing async timeouts | MediaUploadPreviewScreenViewModelTests, ServerConfirmationScreenViewModelTests (partly), CompletionSuggestionServiceTests | ~24 | `confirmation()` API timing out (`DeferredFulfillmentError()`). Could be slow simulator, missing event, or SDK behavior change. |
| **C** | Locale leak (test runs in RU) | DateTests | 2 | Simulator locale persisted between sessions (we set it to Russian during manual smoke test). Tests expect English. |
| **D** | Test fixture / SDK API drift | MediaUploadingPreprocessorTests, MediaProviderTests, RoomRolesAndPermissionsScreenViewModelTests, VoiceMessageRecorderTests | ~13 | Tests reference setup that no longer holds — e.g., `roomProxy.updatePowerLevelsForUsersCalled` returning false suggests mock setup or SDK API drift. |
| **E** | Unknown / unclassified | TimelineMediaPreviewViewModelTests, TimelineViewModelTests, RoomDetailsScreenViewModelTests | ~12 | Need individual investigation. |

Note: counts add up to ~89 because some tests fail with multiple `recorded an issue` lines (each counted in suite totals); 67 is the count of **unique failed test functions** (verified via `grep -oE "Test [a-zA-Z_]+\(\)" | sort -u | wc -l`).

---

## Approach — 4 phases

### Phase 1: Fresh inventory (30 min)

Capture a deterministic, current failure list to work from. Earlier inventory was 2026-05-10; we've had 4 commits since, so the list may have drifted.

**Steps:**
1. Clean DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/ElementX-*`
2. Reset simulator locale to English (`xcrun simctl spawn booted defaults write -g AppleLanguages "(en)"`)
3. Run `xcodebuild test -scheme UnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tee build/test-failures-2026-05-17.log`
4. Parse:
   ```bash
   grep "recorded an issue" build/test-failures-2026-05-17.log \
     | sort -u \
     > build/test-failures-2026-05-17-list.txt
   ```
5. Save final per-suite count + per-test name list to `documentation/test-baseline-post-sync.md` for future deltas.

**Outcome:** A canonical list of every failing test by name + suite + assertion message. This list is what we work from in Phase 3.

---

### Phase 2: Categorize each failure (1–2 hours)

For each of the ~67 failures, look at the assertion message and bucket into A/B/C/D/E.

**Method:**
For each failed test, grep the source file for the assertion line:
```bash
grep -A2 "recorded an issue.*TEST_NAME" build/test-failures-2026-05-17.log
```
Look at the `Expectation failed:` line. The pattern usually tells the category:

- `→ "https://ucmatrix.org/..."` vs `"https://matrix.to/..."` → **A** (rewrite test)
- `→ "matrix.ucmeet.org"` vs `"matrix.org"` → **A** (homeserver test)
- `analyticsConfiguration → nil` vs non-nil → **A** (analytics-disabled)
- `Caught error: DeferredFulfillmentError()` → **B** (async timeout)
- `→ "Сегодня"` vs `"Today"` → **C** (locale)
- `mock.someCalled → false` when test setup said true → **D** (mock/SDK drift)
- Anything else → **E** (investigate per-test)

**Output:** `documentation/test-failure-categorization-2026-05-17.md` — a table with one row per failing test, columns: suite, test name, category, expected-vs-actual snippet, proposed fix.

---

### Phase 3: Fix per category (8–12 hours)

Work order: A → C → D → E → B. Reasoning: A is mechanical and reduces count fastest (build momentum); C is one-line locale enforcement in `setUp`; D-E need investigation but are bounded per-test; B is async — leave for last because investigation cost is highest.

#### Category A — Update UCMeet customization assertions (~38 tests, 2–4 hours)

These tests are wrong because they assert upstream defaults we changed. Updating them to reflect our behaviour is a one-line change per assertion, with an explanatory comment so the customization doesn't get "fixed back" by a future sync.

**Subcategory A.1 — Permalink rewrite (matrix.to → ucmatrix.org), ~28 tests:**

Suites: `AttributedStringBuilderTests`, `ComposerToolbarViewModelTests`, `RoomEventStringBuilderTests`, `RoomDetailsScreenViewModelTests`, `CompletionSuggestionServiceTests`.

Pattern:
```swift
// Before:
#expect(run.link?.absoluteString == "https://matrix.to/#/@user:matrix.org")
// After:
#expect(run.link?.absoluteString == "https://ucmatrix.org/#/@user:matrix.org",
        "UCMeet: outgoing permalinks rewritten to ucmatrix.org (URL.replacingMatrixToHost) since matrix.to is blocked in Russia")
```

For ComposerToolbarViewModelTests RTE-related ones (`userMentionPillInRTE`, `roomMentionPillInRTE`, `selectedRoomSuggestion`, `selectedUserSuggestion`): same pattern but the assertion is on the HTML output (`<a href="...">`). Both `https://` and `&quot;` may need escaping — read the actual assertion line to get the exact format.

Files to touch (and approximate test counts each):
- `UnitTests/Sources/AttributedStringBuilderTests.swift` — ~10 tests (userIDLink, roomAliasLink, userIDMentionAtachment, roomAliasMentionAttachment, restoreAmbiguousMention, restoreMixedMentionsInPlainText, restoreUserMentionInPlainText)
- `UnitTests/Sources/ComposerToolbarViewModelTests.swift` — ~6 tests (selectedUserSuggestion, selectedRoomSuggestion, userMentionPillInRTE, roomMentionPillInRTE, userSuggestionsIncludingAllUsers)
- `UnitTests/Sources/RoomEventStringBuilderTests.swift` — ~5 tests
- `UnitTests/Sources/CompletionSuggestionServiceTests.swift` — ~2 tests

**Subcategory A.2 — Homeserver (matrix.org → matrix.ucmeet.org), ~3 tests:**

Suites: `AuthenticationServiceTests`, `ServerConfirmationScreenViewModelTests`.

Pattern:
```swift
// Before:
#expect(service.homeserver.value == LoginHomeserver(address: "matrix.org", loginMode: .unknown))
// After:
#expect(service.homeserver.value == LoginHomeserver(address: "matrix.ucmeet.org", loginMode: .unknown),
        "UCMeet: appSettings.accountProviders is ['matrix.ucmeet.org']")
```

Files: `UnitTests/Sources/AuthenticationServiceTests.swift`, `UnitTests/Sources/ServerConfirmationScreenViewModelTests.swift`.

**Subcategory A.3 — Analytics disabled (~7 tests):**

Suite: `AnalyticsTests`.

Tests assume `analyticsConfiguration != nil`. We set it to nil via `Secrets.swift` (postHogHost / postHogAPIKey = nil, see AppSettings line ~285).

Approach: either (a) update each test to assert nil-analytics behaviour, or (b) skip the entire suite with a `@Suite(.disabled("UCMeet has analytics disabled — see Secrets.swift"))` annotation. Option (b) is cleaner — these tests test a feature we don't use.

**Subcategory A.4 — Static room summary / power levels (~few tests):**

Suite: `RoomRolesAndPermissionsScreenViewModelTests` — `demoteToMember`, `demoteToModerator`, `notificationCustomMode`, `notificationDefaultMode`. These look like they may be **D**, not A — need to read the assertions in Phase 2 to confirm.

#### Category C — Reset simulator locale (5 min, 1 commit)

Easiest fix. Two failing tests in `DateTests` (`dateSeparatorFormatting`, `senderPrefix`) compare against English strings but the simulator was left in Russian from manual smoke testing.

Fix: add `setUp` to force English locale at test start. Look at how Element X upstream handles this — probably already has a pattern; otherwise:
```swift
@Test func dateSeparatorFormatting() throws {
    // ensure deterministic locale regardless of simulator state
    Locale.current = Locale(identifier: "en_US")
    // ... existing test body
}
```

Or set in test plan / scheme: prefer `xctestplan` configuration to force locale. Inspect `UnitTests/SupportingFiles/UnitTests.xctestplan` for whether locale is already set.

#### Category D — Test fixture / SDK API drift (~13 tests, 2–3 hours)

Per-test investigation. Cluster by symptom:

**D.1 — MediaUploadingPreprocessorTests (~9 tests):** image/video/audio processing tests. Failures may be missing test fixtures or codec library changes in iOS 26.4.1. Read the test, look at expected file path, check if the fixture exists.

**D.2 — MediaProviderTests (~4 tests):** `whenLoadImageFromSourceAndImageNotCachedAndRetrieveImageFails_*`. Likely the underlying `KingfisherManager` API or mock setup drifted from upstream — recent dep bump from Kingfisher 8.x.

**D.3 — RoomRolesAndPermissionsScreenViewModelTests (~4 tests):** if assertions like `updatePowerLevelsForUsersCalled → false`, this is a JoinedRoomProxyMock that wasn't called. Check whether the test setup matches the post-sync mock API. SDK 26.05.06 may have renamed `updatePowerLevels` to something else and the mock wasn't regenerated.

**D.4 — VoiceMessageRecorderTests (~3 tests):** AudioEngine failure messages. Likely simulator audio device issue (no microphone in CI). May need `.disabled` for simulator-only environments.

#### Category E — Unknown (~12 tests, 1–3 hours)

`TimelineMediaPreviewViewModelTests`, `TimelineViewModelTests`, `RoomDetailsScreenViewModelTests`. Need per-test investigation in Phase 2 before deciding fix.

**Possibility:** these may genuinely have real regressions from the merge. If we find any, they're the most valuable bugs to fix — they indicate behaviour that broke during the SDK 26.05.06 upgrade or OIDC→OAuth rename.

#### Category B — Async timeouts (~24 tests, 3–6 hours, LAST)

Hardest to investigate. Failures all have `Caught error: DeferredFulfillmentError()`. This comes from Swift Testing's `confirmation()` API: the test sets up an expectation that an event will fire within a default timeout (probably 1s), and the event never fires.

Three possible causes per test:
1. **Test environment too slow** — increase timeout via `confirmation(expectedCount: 1, isolation:, sourceLocation:)` or wrap in `withTimeout()`. Cheapest if it works.
2. **Event genuinely not firing** — real bug, probably introduced by SDK API change. Need to debug the trigger path.
3. **`confirmation()` semantics changed** in Swift Testing — upstream may need a `confirmation(within:)` migration.

Approach: for each failing test, first try increasing timeout to 10s. If still fails, dig into trigger path. If multiple tests in the same suite all timeout, suspect a common dependency (e.g., a stalled mock).

Specific suites:
- `MediaUploadPreviewScreenViewModelTests` — 22 tests, all timeouts. Common dependency: probably the upload preview state machine. Investigate once for the suite, then fix-all.
- `ServerConfirmationScreenViewModelTests` — 12 tests; 9 are about `confirmLoginWithoutConfiguration` / etc. Likely same root cause.
- `CompletionSuggestionServiceTests` — 2 tests (loadingRetriedOnReconnection).

---

### Phase 4: Verify and document (1 hour)

1. Re-run full UnitTests: `xcodebuild test -scheme UnitTests` — confirm 0 unique failures (or N documented and intentional with `@Suite(.disabled)` reason).
2. Commit per-category in logical chunks (A.1, A.2, A.3, A.4, C, D.1-D.4, E, B) so the commit history is reviewable.
3. Push and watch CI go green.
4. Update `CLAUDE.md` Unit tests row: from `1016/67` to `N/0` (or whatever).
5. Update `documentation/progress_log.md` with the triage outcome.
6. Snapshot the new baseline to `documentation/test-baseline-post-triage.md` so future syncs have something to diff against.

---

## Critical files

| File | What changes |
|---|---|
| `UnitTests/Sources/AttributedStringBuilderTests.swift` | ~10 assertion updates (A.1) |
| `UnitTests/Sources/ComposerToolbarViewModelTests.swift` | ~6 assertion updates (A.1) |
| `UnitTests/Sources/RoomEventStringBuilderTests.swift` | ~5 assertion updates (A.1) |
| `UnitTests/Sources/CompletionSuggestionServiceTests.swift` | ~2 assertion updates (A.1) |
| `UnitTests/Sources/AuthenticationServiceTests.swift` | ~2 assertion updates (A.2) |
| `UnitTests/Sources/ServerConfirmationScreenViewModelTests.swift` | ~3 assertion updates (A.2) + investigate timeout cases (B) |
| `UnitTests/Sources/AnalyticsTests.swift` | Either 7 assertion updates OR `@Suite(.disabled)` (A.3) |
| `UnitTests/Sources/DateTests.swift` | Force-locale fix (C) OR move to `xctestplan` |
| `UnitTests/SupportingFiles/UnitTests.xctestplan` | Possibly add forced locale (C) |
| `UnitTests/Sources/MediaUploadingPreprocessorTests.swift` | Per-test investigation (D.1) |
| `UnitTests/Sources/MediaProviderTests.swift` | Mock / Kingfisher drift (D.2) |
| `UnitTests/Sources/RoomRolesAndPermissionsScreenViewModelTests.swift` | Mock regeneration / SDK rename (D.3) |
| `UnitTests/Sources/VoiceMessageRecorderTests.swift` | Possibly `@Suite(.disabled("simulator audio"))` (D.4) |
| `UnitTests/Sources/TimelineMediaPreviewViewModelTests.swift` | Per-test investigation (E) |
| `UnitTests/Sources/TimelineViewModelTests.swift` | Per-test investigation (E) |
| `UnitTests/Sources/RoomDetailsScreenViewModelTests.swift` | Per-test investigation (E) |
| `UnitTests/Sources/MediaUploadPreviewScreenViewModelTests.swift` | 22 async-timeout fixes (B) — investigate root cause then apply uniformly |

---

## Risks

| Risk | Mitigation |
|---|---|
| Some Category D failures hide real regressions from the merge | Treat any genuinely-failing assertion in D/E as a code bug, not a test bug. Don't reflexively update the assertion to match observed behaviour. |
| Category B timeouts persist after timeout increase → real async deadlock | Allocate extra time in Phase 3; if a deadlock is real, fix the underlying code |
| Category D mock drift requires Sourcery regen which might cascade | Run `sourcery` from the Tools dir if mocks are outdated, may produce more changes |
| New upstream sync arrives mid-triage | Coordinate: don't sync upstream during this work |
| Some tests are environment-dependent (simulator vs CI runner) and won't repro | Document per-suite; use `@Suite(.disabled("known environment-only"))` with clear reason |

---

## Time estimate

| Phase | Time |
|---|---|
| Phase 1 (gather) | 30 min |
| Phase 2 (categorize) | 1–2 hours |
| Phase 3.A (UCMeet customization assertions, 38 tests) | 2–4 hours |
| Phase 3.C (locale, 2 tests) | 15 min |
| Phase 3.D (fixtures/mocks, 13 tests) | 2–3 hours |
| Phase 3.E (unknown, 12 tests) | 1–3 hours |
| Phase 3.B (async timeouts, 24 tests) | 3–6 hours |
| Phase 4 (verify + docs) | 1 hour |
| **Total** | **10–20 hours** |

Realistically: **1.5–3 days of focused work**, spread over the week as concentration allows.

---

## Commit strategy

To keep the history reviewable, plan to commit per subcategory rather than as one mega-commit:

1. `test: update AttributedStringBuilder assertions for ucmatrix.org rewrite (A.1 part 1)`
2. `test: update ComposerToolbar mention assertions for ucmatrix.org (A.1 part 2)`
3. `test: update RoomEventStringBuilder + CompletionSuggestionService for ucmatrix.org (A.1 part 3)`
4. `test: update Authentication + ServerConfirmation for matrix.ucmeet.org homeserver (A.2)`
5. `test: disable AnalyticsTests suite (UCMeet analytics is intentionally nil) (A.3)`
6. `test: force English locale to fix DateTests flakiness across locales (C)`
7. `test: MediaUploadingPreprocessor — <specific fix> (D.1)`
8. `test: MediaProvider — <specific fix> (D.2)`
9. `test: RoomRolesAndPermissionsScreenViewModelTests — <specific fix> (D.3)`
10. `test: VoiceMessageRecorderTests — disable on simulator (D.4)`
11. `test: TimelineMediaPreview/TimelineViewModel/RoomDetailsScreen — <specific fixes> (E)`
12. `test: fix async timeout root cause in MediaUploadPreview/ServerConfirmation suites (B)`
13. `docs: post-sync test baseline (962/899/63 → 1016/0/intentionally-disabled-N)`

That's ~13 commits. Each individually small (5–20 lines plus a focused commit message), easy to revert if one introduces issues.

---

## Verification

After Phase 4:

1. `xcodebuild test -scheme UnitTests` → `Executed N tests, with 0 failures` (where N is 1016 minus any disabled suites).
2. CI run on develop should turn green (with the SwiftFormat fix from `e9a4fa79c` already merged).
3. Cross-check the smoke-test runbook (`documentation/smoke_test_post_sync_2026_05.md`) still passes — these test fixes shouldn't have changed any production behaviour.
4. `documentation/test-baseline-post-triage.md` documents the new baseline so the *next* sync has a clean diff point.
5. No code changes to `ElementX/Sources/` outside what's strictly necessary for Category D/E fixes (if any real regressions found, those go in production code with their own justification).

---

## Decision points the user might want to weigh in on

1. **Category A.3 — AnalyticsTests:** disable the whole suite vs update assertions individually?
   - Disable: cleaner; we don't use analytics, why test it?
   - Update: keeps coverage if we ever re-enable; more work now.
   - My recommendation: **disable with explanatory annotation**.

2. **Category D.4 — VoiceMessageRecorderTests on simulator:** simulator has no real mic. Tests use AudioEngine which fails in simulator.
   - Skip on simulator with `@Suite(.disabled(if:))` based on `ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]`?
   - Or run them, expect failure, and mark as known-environment-limitation?
   - My recommendation: **disable when running on simulator** with a clear reason string.

3. **Category B — async timeouts:** if I find the root cause is a slow simulator (CI runners are slower than my Mac), do we bump timeouts globally or per-test?
   - Per-test: more surgical, smaller blast radius.
   - Global: one place to tune.
   - My recommendation: **per-test for now**; revisit if a pattern emerges.

These are decisions I can make solo if you trust the recommendations; flagging in case you want different defaults.

---

*Plan prepared 2026-05-17. Approved-by: TBD. Estimated to land between 2026-05-18 and 2026-05-22 depending on focus time available.*
