# CubeFlow development closeout after 0.15.0

This record supersedes the open acceptance items in the earlier investigations where explicitly noted. It is not a distribution or deployment checklist.

## Baseline and version

- Git comparison anchor: `39db5d78d` (sets the iOS app to 0.15.0, Build 1). There is no 0.15.0 tag. Local archives confirm that version/build pair but do not identify an exact uploaded source commit.
- Two commits already followed that anchor before this cycle was organized: `53666e4a3` adds TNoodle privacy packaging validation and evidence; `82b455c39` adds the pinned source-delivery inventory and verifier. Neither is a new app feature or proof that the native framework's outstanding provenance gaps are closed.
- Recommend **0.16.0, Build 1** for the next development version: new user-facing capabilities as well as reliability fixes, with a fresh build sequence consistent with 0.15.0. Xcode version settings remain unchanged.

## Shipped in the development worktree

- Timer: inline keypad and shared manual-time parsing with Fixed/Smart interpretation, context-safe startup scramble reservation and prefetch, corrected native puzzle mapping, same-state FMC practice scrambles, and inspection Exit in Cards and Classic. Exit preserves the scramble/session/event, cancels inspection without recording a result, and uses either a 48 pt untinted circle or a native UIKit tinted capsule. [Timer and manual input](performance-experience-overhaul-nov02.md) / [FMC](fmc-battle-performance-nov02.md).
- Smart Cube: verified target checkmark and manual/physical inspection re-entry; scoped target retirement; guidance cancellation and stale-state protection; on-demand rendering and rapid-turn catch-up; device-management and connection refinements. WeiPo 2x2 has checkpoint progress and authoritative PBL completion/persistence fixtures, not arbitrary off-path recovery. [Smart Cube evidence](physical-feedback-nov08.md).
- Local Battle: per-player mixed inputs, device ownership, readiness and scoring, event selection, handicap, and independent configuration panels. [Battle evidence](performance-battle-sharing-nov03.md).
- Data and Sessions: restored SwiftUI Select/X, native Search accessory, adaptive direct Move/Delete, UIKit prominent destructive controls, Sessions Edit/Done alignment and enabled-state feedback. Large sessions use more targeted persistence, indexing, search, and statistics work. [Toolbar history](git-animation-recovery-nov09.md) / [Performance evidence](native-toolbar-cjk-performance-nov09.md).
- Competition and Explore: cache-first delivery and navigation guards, noteworthy competitions, official participation/results presentation, modern CubingChina Live progress/advancement and score-free roster previews, native CJK heading and organizer HTML rendering fixes, Competition Report and Result Highlight image export. [Live evidence](cubingchina-live-progress-nov02.md) / [Sharing and performance](comprehensive-performance-reliability-nov03.md).
- Shared improvements: defer unvisited tab construction while retaining mounted navigation, reuse diagram scripts and date formatting, reduce chart, algorithm grouping and public-data computation, and expand localized UI strings. Keep simulator measurements separate from device launch, GPU, BLE, and energy performance.

## Acceptance and deferred work

| Area | Latest status |
| --- | --- |
| Inspection Exit and Smart Cube re-entry | Physically accepted, including final circle proportions/clearance and the UIKit capsule. Complete; do not reopen. |
| Data and Sessions UI | Physically accepted. Earlier toolbar animation, rectangle, title, and button investigations are historical, not current blockers. |
| Competition Filter rapid reopen | Intentionally deferred. Earlier physical evidence remains on record; no claim of a latency fix. |
| WeiPo V5 AI 2x2 | Physical verification intentionally deferred because hardware is unavailable. Automated results do not certify the exact hardware sequence or latency. |
| Other boundaries | iOS 15 is the deployment target, not an exhaustive old-OS runtime check. Hardware performance, real live-provider changes, and the planned WCIF personal dashboard remain separate work. |

Previously saved evidence includes broad November 9 unit results (848 XCTest, six skipped, zero failures; 359 Swift Testing cases passed) and later focused iOS 26.5/27.0 checks for Data/Sessions and inspection Exit. These are results from their recorded source snapshots, not a claim that the whole final tree was rebuilt or retested during commit preparation.
