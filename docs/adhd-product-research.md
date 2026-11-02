# Helping people start, continue and finish

Research reviewed on 2 November 2026 for Three. Three Claude Opus 5.5 agents investigated ADHD evidence, native interaction design, and blocker feasibility. A further Claude design pass specified the blocker screens.

The strongest relevant evidence supports organization, planning and problem-solving within broader ADHD interventions. It does not establish that an individual timer, checklist or blocking feature improves ADHD symptoms. Three's feature choices are product hypotheses informed by that evidence.

## Evidence and its limits

| Source | Evidence | Limit for Three |
| --- | --- | --- |
| [Safren et al., 2010](https://pubmed.ncbi.nlm.nih.gov/20736471/) | A randomized trial of 86 adults with persistent ADHD symptoms despite medication found better symptom outcomes with a 12-session CBT program than an attention-matched comparison. | A therapist-delivered treatment package does not prove the effectiveness of an isolated app feature. |
| [Solanto et al., 2010](https://pubmed.ncbi.nlm.nih.gov/20231319/) | A trial of 88 adults evaluated a program targeting time management, organization and planning against supportive therapy. | Group treatment, not a focus-planner trial. |
| [Matsumoto et al., 2024](https://pubmed.ncbi.nlm.nih.gov/39732478/) | A component network meta-analysis of 43 randomized trials associated organizational strategies with treatment response and problem-solving with reduced inattention. | The population was not restricted to adults. Component estimates do not isolate Three's proposed interactions. |
| [NICE NG87](https://www.nice.org.uk/guidance/ng87/chapter/recommendations) | The reviewed guidance describes environmental modifications such as reducing distractions, written instructions, and shorter focus periods with movement breaks. | The official page returned HTTP 403. The researcher read a [mirror of the guideline](https://docs.bvsalud.org/biblioref/2022/02/1357854/attention-deficit-hyperactivity-disorder-diagnosis-and-managem_kempx2v.pdf), marked last updated September 2019. Current wording was not verified. |

The search did not identify direct adult-ADHD trials of software site blockers, fixed Pomodoro timing, streaks or body-doubling app features. That is a search limit, not proof that no such study exists.

## Priorities for Three

| Priority | Feature | Why it earns consideration | How to judge it |
| --- | --- | --- | --- |
| Build in this pass | Show the next unchecked step in Now, with a completion control. Hide the row when there are no steps. | A concrete action is more useful at the moment of work than a step count. It uses the existing checklist. | Check whether the user can identify and complete the next action without returning to the task card. |
| Build in this pass | Drag Today cards to reorder, with a clear insertion cue and menu alternatives. | The user requested it. Existing persisted task order already determines priority and the next task. | Verify both drag directions, cancellation, persisted order, and preservation of selection, drafts and timer state. |
| Build in this pass | Selected website/app blocking during focus sessions and recurring focus hours. | The user requested it. Reducing distractions is consistent with the reviewed guidance, although the blocker itself lacks direct trial evidence. | Verify enforcement and expiry. Make coverage gaps visible. Later evaluate whether the user keeps it enabled and whether bypasses become less frequent. |
| Next small feature | Give a Stuck reflection a recovery action, such as adding a smaller next step. | The current app records Stuck but offers no dedicated problem-solving path. | Check whether the user resumes that task after choosing a recovery action. |
| Later | One start notification for an explicitly scheduled task. | A visible plan is currently separate from a timely start cue. | Compare scheduled start with actual start locally. Fire once and avoid duplicate calendar alarms. |
| Keep existing behavior | Adjustable sessions and optional breaks. | These already provide flexibility. The reviewed evidence does not justify enforcing one fixed work/break cycle. | Preserve user control and avoid repeated break prompts. |

These suggested measures do not authorize new telemetry. Existing local records and observed user paths are sufficient for the initial evaluation.

## Features that do not earn their cost yet

Do not add points, badges, confetti, mandatory step-writing, repeated reminders or social rooms in this pass. Avoid claims about dopamine. A nonconsecutive weekly completion summary is a better candidate for later review than a streak that resets after one missed day. That preference is a product judgment, not a clinical finding.

## Design direction

Claude selected a single focal column for Now. It groups the task and next action, the dial and time, then the controls. The dial grows with the available pane size while text keeps its existing type roles. Empty, paused, break and finished states receive explicit treatments.

The choice follows Apple's guidance to adapt proportions in [full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) and to offer alternatives to [drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop). Exact dial limits and spacing are Three design decisions. Liquid Glass remains on the existing dial, cards and controls. Plain pane headers and invisible resize dividers remain.

## Blocker delivery boundaries

The initial implementation targets Chrome through a Manifest V3 extension and [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging). The extension requires a deliberate setup step in each profile. Guest sessions, missing or disabled extensions, other browsers and unsupported private browsing remain uncovered.

Native app interception uses [NSRunningApplication.hide()](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide()). Hiding preserves the process and its documents. It is bypassable and requires Three to be running; it does not stop audio or notifications.

Durable Safari extension support remains gated on an Apple signing identity. Apple's [Safari extension instructions](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension) describe the development-only handling of unsigned extensions. Native macOS Screen Time support and a system-wide network filter are not substitutes available to this ad-hoc SwiftPM build.

The initial rules are explicit domains or app bundle identifiers. Presets add visible domain entries for X/Twitter, Reddit and YouTube. Domains include their subdomains. Focus hours use local wall-clock times and support overnight windows. No rules or schedules are enabled by default.

Blocking status must distinguish policy activity from actual browser connection and app enforcement. A protection expiry is labeled as a blocking expiry, not as the timer's end. Temporary exceptions are deliberate human actions in Three. Safari and other unconfigured browsers are never hidden automatically.

The blocker screens avoid distraction counters and guilt-focused wording. They explain what is blocked, which task or focus-hours window applies, when protection changes, and how to return to work.
