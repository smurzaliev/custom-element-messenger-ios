# UnitTests Baseline — Post-Triage 2026-05-17

> Snapshot of the UnitTests scheme **after** the post-sync test-failure triage
> on `chore/fix-post-sync-test-failures` was completed.
> Companion to `post_sync_test_triage_plan.md` (the plan we executed).
> Diff against this when the next upstream sync arrives to detect regressions
> introduced by upstream vs. environmental drift.

## Headline numbers

| Metric | Value |
|---|---|
| Total tests run | **1024** |
| Failures | **0** |
| Suites | 130 |
| Wall-clock | ~157 s (iPhone 17 Pro / iOS 26.4.1 simulator) |

## How to reproduce

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/ElementX-*
xcrun simctl spawn booted defaults write -g AppleLanguages "(en)"
xcodebuild test \
  -scheme UnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Expected: `Executed 1024 tests, with 0 failures` (within the UnitTests bundle;
the All-tests rollup also reports PushProviderTests, LocalizationTests, and
FirebaseIntegrationTests passing).

## Intentionally disabled coverage

These were disabled by us during the triage. Re-enable them only if the
underlying feature is wired back up.

| Where | Type | Reason |
|---|---|---|
| `UnitTests/Sources/AnalyticsTests.swift` | `@Suite(.disabled(...))` | UCMeet ships with analytics nil (`Secrets.postHogHost` / `postHogAPIKey` set to nil). Re-enable if PostHog ever gets wired up. |
| `UnitTests/Sources/BugReportServiceTests.swift::configurations` | `@Test(.disabled(...))` | UCMeet ships with rageshake nil (`Secrets.rageshakeURL` set to nil), so `BugReportService.configuration` is `.disabled` instead of `.url(...)`. Re-enable if rageshake is restored. |

Upstream-disabled (pre-existing, NOT our work):

- `ElementCallServiceTests::callIsTimingOut` — upstream commit `c33cb5671` flagged it flaky.

## Triage commit chain (for blame-on-next-sync)

8 commits on `chore/fix-post-sync-test-failures`, oldest first:

1. `52136f668` — disable AnalyticsTests + BugReportService.configurations (A.3)
2. `91c632442` — ucmatrix.org permalink assertions (A.1)
3. `565f62200` — matrix.ucmeet.org homeserver assertions (A.2)
4. `32e17fe90` — force en/US locale in `UnitTests.xctestplan` (C)
5. `3b83bf229` — production fix: mention-attachment regression from permalink rewrite
6. `a3fe5f775` — undo wrong A.2 change to ServerConfirmation.elementProRequired (serverName flows from mock `client.server()`, not `appSettings.accountProviders`)
7. `293cca66b` — `@Suite(.serialized)` on VoiceMessageCacheTests (Swift Testing parallelism races on shared on-disk dir)
8. `c77dd0024` — docs update: CLAUDE.md + progress_log.md

## Categories from the plan, status

| Category (plan) | Plan estimate | Actual |
|---|---|---|
| A.1 — ucmatrix.org permalink assertions | ~28 tests | done in 1 commit |
| A.2 — matrix.ucmeet.org homeserver | ~3 tests | done in 1 commit, one wrong target reverted later |
| A.3 — Analytics disabled | ~7 tests | suite-disabled |
| C — Locale (DateTests) | 2 tests | xctestplan-forced locale fixed it |
| D.1 — MediaUploadingPreprocessor | ~9 tests | **did not actually fail** in post-sync run |
| D.2 — MediaProvider | ~4 tests | **did not actually fail** |
| D.3 — RoomRolesAndPermissionsScreenViewModel | ~4 tests | **did not actually fail** |
| D.4 — VoiceMessageRecorder | ~3 tests | **did not actually fail** (only VoiceMessage **Cache** Tests failed) |
| E — TimelineMediaPreview / TimelineViewModel / RoomDetails | ~12 tests | **did not actually fail** |
| B — Async timeouts (MediaUploadPreview, ServerConfirmation, CompletionSuggestion) | ~24 tests | **did not actually fail** in fresh run |
| (new D not anticipated) — VoiceMessageCacheTests file-system race | – | 3 tests, fixed via `.serialized` |

Take-away: the plan over-estimated work by ~50 tests. The bulk of the post-sync
failures were category A (mechanical assertion updates) plus locale leak;
categories B/D/E in the plan never materialised once A and C were applied.
The only unanticipated failure was VoiceMessageCacheTests' Swift-Testing
parallelism race on a shared on-disk directory.

## When to update this doc

- After every upstream sync's "run UnitTests once, count failures" step
- Add a new row to the table with the new total/failure counts and the date
- Don't replace this baseline until a *new* triage cleans the next sync's failures
