# CubingChina Live Progress and Conservative Advancement

Date: 2026-11-02 (Asia/Shanghai). One coordinated App-only task on local `main`. All pre-existing dirty changes are preserved. No upstream/backend modification, write request, OAuth authorization, physical-device operation, commit, push, release, or deployment.

## Investigation and Evidence

Relevant ownership chain:

1. `CompetitionService.resolveCubingChinaLive` validates competition identity and builds the modern bootstrap from round metadata.
2. `CompetitionCubingLiveSession` owns the modern session and selector binding; explicit initial options carry deep links.
3. `CubingChinaModernLiveSession` owns selected-round REST state, bounded per-round caches, SSE revisions/sequences, and adjacent-round evidence.
4. `CubingChinaUnifiedLiveContent` uses shared selectors, surfaces, result rows/cards and grouped Records/Podiums presentation.
5. `CubingChinaLivePresentation` adapts authoritative records and advancement evidence. `CompetitionAdvancementCalculation` computes only CubingChina bounds; WCA Live transport/navigation is unchanged.

Historical reports reviewed: `cubingchina-modern-live-oct11.md`, `unified-results-cubingchina-live-oct12.md`. They distinguish archive verification from unverified live projection parity. Current code, not their older feature inventory, is authoritative.

Upstream was inspected at commit **33ceab1efd8b7e1d0596cebe7e7af047142ded74**:

- [live.js](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/public/f/js/live.js): legacy highlights use next-round limits; dual combined views use the better result of a pair. This older UI is not the modern REST contract.
- [ResultHandler.php](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/websocket/handler/ResultHandler.php): ordinary fetch reads round entries, including zero-valued placeholders before closure; closed rounds can omit unrecorded rows. Entry updates can change open to live. Refresh constructs actual server-owned next-round rows; CubeFlow does not invoke that operation.
- [LiveEventRound.php](https://github.com/CubingChina/cubingchina/blob/33ceab1efd8b7e1d0596cebe7e7af047142ded74/protected/models/LiveEventRound.php): legacy status values are open=0, finished=1, live=2. Dual rounds are the first pair, with combined ranking rather than ordinary elimination between them.
- [WCA regulations, version April 1, 2026](https://www.worldcubeassociation.org/regulations/#9p): ranking/result-based progression, the 25% elimination restriction, and all-DNF/DNS ineligibility; [Dual Rounds](https://www.worldcubeassociation.org/regulations/#9v) have separate rules.

Read-only current production checks used [round metadata](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/rounds), [complete round response](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026/live/results/333/1), and [competition metadata](https://api.cubing.com/competitions/Beijing-Autumn-Rivalry-2026). The 3x3 round-one response contains 325 entries. The modern round response is `{round, results}`, without a pagination envelope or independent expected-roster count. Competition metadata explicitly exposes WCA type and per-event `dualRounds`.

The website's current public client was also inspected (`DJ4m7igK.js`, `By9NE9nW.js`, `BUqrEU_a.js`, captured under the evidence directory). Its status/progress default, attempt-zero treatment, full-array/recorded counts, and separate projected/confirmed sets support the behavioral investigation. No implementation code was copied. These observations do not establish a public third-party API stability promise or complete production parity.

## Confirmed Causes and Corrections

### Default selection

The old bootstrap used the first live array item, otherwise the greatest 3x3 round number, otherwise array index zero. The event selector independently chose the greatest round number. Thus a future final could be chosen despite finished earlier rounds.

Both now use the same deterministic progress selector: active live round, otherwise completed round, otherwise started-but-not-live metadata, otherwise earliest upcoming round. Round number orders within an event; available finish/start timestamps compare progress across events, with a stable 3x3/event/ID fallback when timestamps cannot discriminate. Each event is reduced before cross-event comparison; input-array order does not decide the default.

Initial entry and non-explicit re-entry can reconsider the default using refreshed metadata. Explicit user/deep-link selections remain pinned. SSE metadata refresh does not navigate the user. The bridge synchronizes only actual modern selection changes, not every publication, preventing unrelated publications from replacing a pending UI selection. Official Results navigation is untouched.

### Empty results

The old branch checked only `results.isEmpty`, so populated zero-attempt rosters rendered a score table.

Presentation now distinguishes a real recorded attempt (positive, DNF=-1, DNS=-2) from zero/unrecorded values. A genuinely unstarted round with no recorded attempts shows localized **Not Started**. A started/live/finished round without recorded attempts shows **No Results Yet**. Actual DNF/DNS entries remain recorded results. `startedAt` prevents a previously started open round from being mislabeled unstarted.

Authoritative placeholder competitors remain visible as participant names through the existing shared row component, without an empty score table. Normal recorded-result rows/cards are unchanged. English, Traditional Chinese, and Simplified Chinese use the existing `CompetitionPublished.strings` architecture.

### Yellow advancement

The suspected branch was real: if the adjacent round was open/live/finished, the adapter returned only members of its roster, or an empty map while that roster was unavailable. The selected results renderer invoked that adapter, while grouped views used cached evidence. This both suppressed legitimate possible states and made results depend on whether an adjacent request had completed.

Local mathematical assessments now coexist with authoritative next-round membership. Missing/delayed rosters no longer erase valid yellow. A finished source plus an already-started, nonempty authoritative next roster uses that roster to account for withdrawals/replacements rather than reinserting excluded local candidates.

Another demonstrated boundary was corrected: roster/reranking notifications with empty upserts/removals are not proof that the participant universe is unchanged. They invalidate the affected full snapshot and trigger targeted REST recovery instead of committing an empty delta as complete roster evidence.

## Advancement Semantics

Internal states are separate: **authoritative**, **guaranteed**, **possible**, **eliminated**, **undetermined**. The unchanged UI maps the first two to green, possible to yellow, and the last two to normal appearance. Existing finished-final podium colors are preserved; they are not next-round advancement claims.

For ordinary independent rounds:

- A guarantee requires a complete, validated current-roster snapshot, unique result/user/registration identities, recognized rules/format, and verified ordinary WCA event metadata. Grouped Records/Podiums subsets cannot establish population counts or guarantees.
- Full snapshot means the current roster returned by the unfiltered round REST endpoint, reconciled through contiguous SSE updates at its current revision/stream epoch. It does **not** mean an external audit of registrations or a guarantee against later organizer corrections/joins. Unknown, invalid, gapped, stale, or subset evidence cannot authorize green.
- Positive attempts, DNF, DNS, zero/unrecorded attempts, trailing cutoff zeros, holes, duplicate identities and overflow are distinguished. Cutoff failures do not acquire invented averages. An average without a valid qualifying average is conservatively undetermined; an entirely failed completed result is eliminated. Unsupported formats and unknown rules do not produce local highlights.
- Remaining attempts receive optimistic lower-bound outcomes for qualification analysis only. Published attempts, best, average, and server positions are never changed.
- For a completed qualifying score, count all fixed better-or-equal opponents and every unfinished opponent whose best legal bound can displace/tie it. Boundary ties count against certainty. Best-only formats can be guaranteed before their remaining attempts because a recorded best cannot worsen; unfinished averages cannot.
- For ranking, enforce the announced number and applicable 75% ceiling. For percentage, use possible participating populations from already-recorded entrants through the complete roster, applying floor rounding. Possible new threats increase worst placement until exhausted; beyond that point population-dependent capacity can only increase. Evaluating both endpoints and the threat-count turning point covers the extrema, rather than sampling arbitrary outcomes. Sorted score lists/binary bounds avoid a quadratic opponent scan.
- Yellow means a qualifying outcome remains possible but worst-case certainty is absent; a missing next roster is not elimination. A partial field may retain a rank-supported possible state, never a locally guaranteed one.
- Result-threshold rules require the relevant positive ranking result to be strictly better than the announced threshold, while retaining the applicable elimination ceiling.
- Server-authoritative next-round membership is separate evidence, not a guessed next list. Completed-source membership can reflect official withdrawals or replacements and takes precedence once the next round is underway.

**Dual/combined limitation:** competition metadata is read once per session run through an optional read-only rules transport. Missing/ambiguous policy, non-WCA events, and `dualRounds=true` disable ordinary independent-round inference. The dual pair's combined best-of-two universe is not reconstructed by this change. Authoritative server membership remains usable; local dual guarantees/participants remain undetermined. This is deliberate conservative behavior, not a claim of dual-round parity.

## Next-Round Participants and Concurrency

`CubingChinaLiveParticipant` is presentation-only: competitor identity and source-round key, with no result ID, ranking, attempts, average, best, or encoding/persistence API. It cannot be inserted into the official snapshot/result DTO. Only locally **guaranteed**, not yellow, entrants enter this preview.

The selected round loads at most its immediate predecessor and successor when current full evidence is missing. This permits entering a future round directly without manually visiting its source. Existing per-round cache limits remain 12 entries/20,000 rows; there is no global scan, polling, delay, or repeated failure loop. One public competition-metadata GET supplies WCA/dual policy, never credentials or score mutations. Older mock transports without that optional capability safely lack local guarantees.

Preview identities are deduplicated against current authoritative next-round caches and selected data. Authoritative arrivals replace the inferred representation without overwriting official values. Source corrections, removals, rule/status changes, stream gaps, and cache invalidation retract local guarantees automatically. Participant rows have no result-card action and are labeled as a **local preview without recorded results**.

Adjacent requests retain generation/selection/revision checks, plus stream epoch, per-round event sequence, and owned request identity. Equal-revision SSE corrections cannot be overwritten by an older in-flight REST response or request-pool reuse. A cancelled predecessor/successor task cannot clear its replacement's ownership. Reconnect invalidates prior stream evidence and resynchronizes through the existing bounded recovery. No new broad synchronization was introduced.

## Validation

Evidence: `build/cubing-live-progress-nov02/`. Logs record exact commands; result bundles contain assertions and mounted screenshots. Existing Xcode 27.2/SDK 27.2, iOS 15 app target, existing iOS 26.5 simulator. No software/dependency installation or physical-device access.

- `initial.xcresult`: exposed stale old expectations (future-round defaults and roster-only highlights), plus the unrelated WCA ID assertion conflict. Failures were not counted as successes.
- `progress.xcresult`: first six new deterministic regressions passed.
- `focused.xcresult`: exposed the empty roster-delta recovery bug, subsequently corrected, and the independent Chat-toolbar hierarchy test failure.
- `verified.xcresult`: **62 focused XCTest passed**, zero failures, with two specifically identified checks excluded as described below. Includes advancement, HTTP/SSE, round/session lifecycle, archive adapters, unified results, and nine new progress tests.
- `final-progress.xcresult`: **27/27 advancement and progress tests passed** after the final source change and additional explicit SSE-selection assertions. Includes the 40-person examples, small exhaustive remaining-outcome check, boundary ties, percentage rules, complete/incomplete evidence, DNF/DNS, zero rows, existing cutoff/overflow cases, delayed equal-revision responses, source corrections, authoritative reconciliation, event isolation and deep links.
- Mounted empty-round OCR verifies Not Started, retained participant names, and absence of Average/Best score-table headings. Existing mounted modern light/dark archive checks passed. These are not physical acceptance or complete production-parity proofs.
- One unsigned generic iOS Debug build **passed**, exit 0: `final-unsigned-debug.log`. `CODE_SIGNING_ALLOWED=NO`, no archive or upload. Only an additional test was added after that production build, not application changes.
- `rules-http.xcresult`: the additional public competition-rules GET test **passed** (1/1), verifying the exact route, GET/no credentials, ordinary policy, dual policy and missing-policy refusal. Distinct passing union: **63 tests**, not the sum of overlapping reruns. The two excluded checks above are not counted as passes.
- `git diff --check` and pre-existing dirty-file SHA-256 preservation checks pass.

### Two explicit regression limitations

1. `CubingChinaModernLiveTests.testExactWCAIdentityNoNameCaseOrMissingIDInference`: the existing test rejects lowercase/whitespace, while the unchanged HEAD implementation deliberately uppercases/trims before matching. The initial run failed these assertions. Identity/OAuth implementation and this test's assertions were not changed to manufacture a pass. Excluded from the final green selection, not silently declared passing.
2. `CubingChinaUnifiedResultsTests.testNativeLiveToolbarMountedLightDarkAndNarrow`: expects the private UIKit type name `ToolbarTAMICAdaptorView` in mounted navigation. This run found none and emitted the framework hosting warning. No toolbar production code or that test was changed. The result is unresolved fixture/runtime/toolbar verification, not proof of a production regression or an OS-only cause. Excluded from the final green selection and retained for physical review.

## Physical / Production Acceptance

1. Enter an active competition: live round wins over a future final; between live rounds the default is the latest completed one; all-unstarted chooses the earliest round. Test another event, explicit future round and a Recent Records deep link. Later SSE metadata must not navigate away.
2. Open unstarted rounds with zero-attempt entrants, active rounds without attempts, and rounds containing real DNF/DNS. Verify localized state, retained names and normal recorded-result table respectively.
3. During an ordinary live round, compare green against the announced boundary and remaining unrecorded competitors, including ties and partial averages. Verify yellow remains while adjacent data is delayed/unavailable. No unsupported policy should acquire a guessed green state.
4. Open the next round before its source finishes. Only guaranteed entrants should appear in the local-preview section, with no scores/rank/result card. Observe official roster arrival and source corrections: no duplicates, overwritten values, or retained invalid guarantee.
5. Switch events/rounds rapidly, disconnect/reconnect, background/foreground, and exercise real join/quit/rerank events. No old rows, source corrections, or selection should leak across identities/epochs. Observe Chat toolbar separately due to the failed mounted check above.

No live organizer operation was performed to force these states. Source transport contract changes, undisclosed organizer exceptions and full dual-combined inference remain verification limits.

## Files and Git State

Task changes:

```text
CubeFlow/Views/Shared/CompetitionAdvancement.swift
CubeFlow/Views/Shared/CubingChinaLiveModels.swift
CubeFlow/Views/Shared/CubingChinaLivePresentation.swift
CubeFlow/Views/Shared/CubingChinaLiveTransport.swift
CubeFlow/Views/Shared/CubingChinaModernLiveSession.swift
CubeFlow/Views/iPhone/CubingChinaUnifiedLiveContent.swift
CubeFlow/Views/iPhone/CompetitionTabView.swift
CubeFlow/en.lproj/CompetitionPublished.strings
CubeFlow/zh-Hant.lproj/CompetitionPublished.strings
CubeFlow/zh-Hans.lproj/CompetitionPublished.strings
CubeFlowTests/CompetitionAdvancementTests.swift
CubeFlowTests/CubingChinaModernLiveTests.swift
CubeFlowTests/CubingChinaLiveProgressTests.swift (new)
docs/cubingchina-live-progress-nov02.md (new)
```

The fake transport gains explicit rules evidence; relevant old tests now distinguish mathematical guarantees from roster-only confirmation and use explicit selection where they intend to test a particular source round. Unrelated assertions were not weakened.

The starting 12 modified paths, 13 untracked paths and full patch are recorded in `initial-status.txt`, `initial-dirty-hashes.txt`, and `initial.patch` under the ignored evidence directory. Existing Timer/Smart Cube changes, Info.plist ordering, local scheme settings, prior report/test, and eleven untracked screenshots remain untouched. Final status is retained in `final-status.txt`. No staged changes, deletions, commits, pushes, tags, releases, deployment, or TestFlight upload.

## Closeout

Final whitespace checks (including new files) and SHA-256 checks for all 12 pre-existing modified files passed. Final working tree: 24 modified tracked paths, 15 untracked paths; no staged changes or deletions. Task delta is the 14 paths above. The remaining initial untracked report/test and screenshots were not edited. No production code changed after the passing unsigned build. No test/build task from this pass remains running; the simulator booted for the checks was shut down without erasing it.

Confirmed fixed in code/tests: progress-aware defaults; empty-result semantics; roster-dependent yellow suppression; metadata-only roster recovery; score-free inferred participant reconciliation and stale-response guards. Validated locally, not physically accepted: rendering and active-event flow under those changes. Unconfirmed/outstanding: actual live organizer mutations, physical navigation/VoiceOver/older-iOS behavior, and the Chat toolbar check. Intentionally conservative/unchanged: local Dual/combined progression, unknown policies, official score ownership, the existing shared colors/result-card flow, WCA Live, Timer/Smart Cube/OAuth/Inspection.
