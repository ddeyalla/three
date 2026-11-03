# Readable Trends date axes

The coordinator inspected Terra's retained native screenshot at `/Users/divyanshudv/.t3/worktrees/adhd/t3-e9782d2c/build/verification/non-calendar/final-native-recovery/trends.png`. Every daily tick rendered as a truncated `2026…`, so users could not distinguish the dates. The native numerical values still matched the packaged fixture.

| Before | After | Why |
| --- | --- | --- |
| Twenty-eight full ISO date strings compete for daily-axis space. | Label weekly positions and the final date with the compact `MM-dd` suffix. The full year and range remain in the heading and full dates remain in accessible mark descriptions and value disclosures. | Dates remain distinguishable at the narrow supported width without rotating or animating labels. |
| Sparse ratio charts derive their categorical domain only from available marks. | Supply every report day or week as the domain for each chart. | Missing values keep their chronological position without fabricated zero values or new date conversion. |

`TrendsView.swift` alone changes product behavior. A private axis-content function reuses existing typed civil dates for all five chart views. Core reports, marks, numerical values, read keys, and keyboard actions remain unchanged. Emil design engineering guided the quiet labels and preserved accessible full-date detail. The axis stays categorical so skipped civil dates retain their place.

PASS. `CONFIG=release ./scripts/bundle.sh`, strict deep signing, plist validation, design lint, and `git diff --check` passed after the correction. Logs are `build/verification/non-calendar/trends-axis-release-corrected.log` and `trends-axis-lint-corrected.log`. The first build attempted a custom AxisContent conformance; the platform protocol has no public body-based conformance. The final code returns native AxisMarks from a function. The initial compiler failure is retained in `trends-axis-release.log`.

Native before/after rendering at narrow and wide sizes and independent review remain pending. Compilation is not a visual acceptance claim. No unit test was added for this reversible presentation-only change. The real artifact is the appropriate check.

## Independent source verdict

Codex Sol 6.1 High independently passed `07607eb` relative to `2fc510c`, with no verified findings. The coordinator inspected `/Users/divyanshudv/.t3/worktrees/adhd/t3-cddc4978/.audit/07607eb-axis-review.json`. The review checked complete and sparse domains, empty input, first/final ticks, year-qualified context, and preserved accessible full dates. It verified the frozen app/helper SHA-256 values and strict ad-hoc signature. The helper is byte-identical to the previously reviewed `dbba9ae` helper.

The reviewer ran no build, suite, app launch or desktop interaction. It left only its scratch receipt and no owned processes, and was stopped after delivery. Native rendering remains with Terra on the frozen `07607eb` release. This verdict does not close other acceptance gaps or localize the prior supervisor failure.

## Narrow-width collision correction

Terra's [read-view receipt](readviews-native.md) reproduced date-label truncation at 680 and 1060 points on `07607eb`. The coordinator inspected the saved daily-focus and accuracy screenshots. Five ticks have ample space between them, but the daily categorical labels still truncate. The corresponding weekly axis shows complete dates at the same window width.

| Before | After | Why |
| --- | --- | --- |
| The shared axis leaves label collision resolution at the platform's automatic policy. Daily dates truncate to `1...` at 680 points. | Request Swift Charts' native `.greedy` collision resolution. | The documented policy displays a label when it does not overlap another label. It avoids requesting truncated labels or changing the data domain. |

The one-line change remains in `trendsDateAxis`. Compact date text, selected ticks, full categorical domains, numerical marks, and accessible values stay intact. [Apple's collision-resolution documentation](https://developer.apple.com/documentation/charts/axisvaluelabelcollisionresolution/greedy) supplies the platform behavior. Native rendering is still required to establish the correction at supported widths. No accounting or protocol change is involved.

PASS. The collision-policy candidate passed `CONFIG=release ./scripts/bundle.sh`, strict deep signing, plist validation, design lint, and `git diff --check`. Logs are `build/verification/non-calendar/trends-collision-release.log` and `trends-collision-lint.log`. The app SHA-256 is `00e5ea3483dbf10107f3522e3f428f7ac26cb990a86607ed3e4c75a3aa635ff2`. The helper remains byte-identical to the reviewed `07607eb` helper, with SHA-256 `e2b864559d7e50a68dbeb194d692aee1751fb61834d9c8ac1393aea4ec52f8a2`. The source delta adds no comments or tests. Fresh source review and native rendering remain open.

## Independent collision-policy verdict

Codex Sol 6.1 High independently passed `cb68bd8` against `fbaa3e5`, with no verified findings. The coordinator inspected the report and recorded commands under `/Users/divyanshudv/.t3/worktrees/adhd/t3-5e1f4c92/.audit/collision-review/`. The exact extracted helper typechecked against Charts with a macOS 26 target. Source-extracted tick selection passed lengths zero through 366, sparse inputs, and civil-date boundaries. Source comparison confirmed all five complete domains, marks, numerical values, and full-date accessibility remain unchanged. Frozen identities, hashes, strict signatures, plist checks, and helper byte equality passed.

This is source, API, and artifact proof. The reviewer launched no app and did not observe corrected labels or endpoint visibility. Greedy collision handling may omit overlapping labels. Terra retains the native acceptance gate. The reviewer left only scratch audit files and no owned processes, and the coordinator stopped it after delivery.

## Native collision-policy verdict

Terra passed the recorded truncation check on frozen `cb68bd8`. The coordinator inspected the 600-point daily-focus, 680-point accuracy, and 1240-point daily-focus screenshots in the [native receipt](trends-collision-native.md). Displayed labels are whole at 600, 680, 1060, and 1240 points. Weekly labels remain whole at the tested minimum and wide sizes. Native metrics, chronological positions, missing ratios, tag selection, and the narrow empty state match the packaged fixture.

At the three smaller widths, the daily axes omit both endpoint labels. The coordinator accepts this reduced label density with the existing year-qualified page range and full-date value disclosures. It is a documented presentation limitation, not a missing record or a claim that every tick is visible. No additional axis abstraction or accounting change is warranted by this result. Larger-fixture native timing and other tickets' interaction gates remain open.

Fresh protected-state captures match exactly. Terra stopped its owned processes; Manual Test's previously absent process remains an exception. The coordinator stopped the completed desktop delegate before assigning the next native pass.
