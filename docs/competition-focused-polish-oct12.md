# Focused Competition UI Polish

October 12, 2026. Physical-acceptance corrections to the earlier Results presentation pass. No commit or push; unrelated dirty-worktree changes preserved.

## Changes

1. All three Event/Round selector containers reuse `CompetitionResultListDecoration` directly through the shared surface. The existing continuous 4pt radius, black shadow (0.12 opacity, radius 1.5, y 1), and existing dark ambient shadow are unchanged. No new shadow style.
2. Top Cubers uses subheadline semibold disclosure typography and a full-width 44pt rectangular hit region. The scroll-anchor object, marker, display link and offset-writing implementation were removed entirely. Expansion/collapse changes content height naturally; stable IDs, measured three-visual-row limit, smooth 0.32s animation and the system Reduce Motion branch remain.
3. Official Results / Live / My Results appear above destination navigation. Capsules have a 32pt minimum visual height, 4pt vertical / 10pt horizontal padding and 44pt interaction targets. Native Liquid Glass/material fallbacks, colors, overflow and actions remain. Chat retains its previous dimensions.
4. The common Results/Podiums/Records heading aligns measured glyph ink to the title's first-line capital-height center, using existing glyph metrics and scaled system-font metrics. Event mappings and title semantics are unchanged.

## Verification

- 25 focused tests passed: CompetitionResultsRefinementTests (14) and CubingChinaUnifiedResultsTests (11). Includes six repeated expand/collapse cycles with and without animation in an actual UIScrollView, heading ink-center measurements for 3x3, 7x7 and Bluetooth, and selector/list shadow comparisons. Dark rasterization matches exactly; light comparison permits the measured single 8-bit quantization step. No broad suite.
- `git diff --check` and touched-untracked whitespace checks passed.
- Exactly one final unsigned generic iOS Debug build passed with deployment target iOS 15. Only warning: skipped AppIntents metadata extraction because there is no AppIntents.framework dependency. No production edits followed it.
- Preserved project file, REST/SSE transport/session, CompetitionTabView, global tab container and Explore module match starting hashes.

Logs: `/tmp/cubeflow-focused-polish/focused-pass.log` and `/tmp/cubeflow-focused-polish/final-ios-debug.log`.

Inspected [Live compact layout](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-focused-polish-oct12/live-light-320.png), [dark selector](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-focused-polish-oct12/selectors-actions-true.png), [Top Cubers](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-focused-polish-oct12/top-cubers-320.png), and [aligned heading](/Users/paulsun/Desktop/Projects/CubeFlow/docs/assets/competition-focused-polish-oct12/heading-aligned-777.png). These are native mounted renders, not physical-device acceptance.

Next step: install this build and retest the original selector-shadow and repeated-disclosure failures on the physical device, including system Reduce Motion. Confirm all three selectors, capsule actions/overflow, and Results/Podiums/Records title alignment. Data, navigation and unrelated behavior were not redesigned.
