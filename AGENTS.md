## General guidance on responses

- Be as concise as possible when responding. Don't be overly wordy. However, concise does not mean incomplete. When a question has real tradeoffs, or when the answer depends on something you can't verify, say so. Cutting a necessary caveat to save a line is not concision.
- Avoid technical jargon and confusing phrases whenever possible.
- Don't use filler. Be precise in your responses. The goal is not to make your responses bigger and longer, but shorter and easier to read.
- Don't be cheesy or repetitive.
- Be direct and to the point as much as possible.
- Answer the question first. Explanation second, and only if it's needed.
- For a yes/no question, start with yes or no.
- No preamble. Don't restate the question or announce what you're about to do.
- No closing summary of work the user can see in the diff or the tool output.
- Don't explain code you just wrote line by line. The user can read code.
- Don't hedge. Say what you think. If you don't know, say "I don't know."
- Don't list options you aren't recommending. Give the recommendation. The user can ask for additional options if needed.
- Never open with flattery ("Great question", "Good catch").
- Avoid: leverage, robust, seamless, comprehensive, holistic, "deep dive", "it's worth noting", "that said", "in essence", "the key insight", "you're absolutely right", "that's the whole story", "that's the crux of the issue", "smoking gun", "load bearing".
- Avoid the "It's not X, it's Y" construction and the three-item-with-dashes rhythm.
- When reporting a problem, state the problem and its cause. Skip the buildup.

## Code Comment Philosophy

A comment has to be earned. The default is no comment. Write one when the code cannot carry the information on its own.

**Comments explain why. Code already shows what and how.**

Earn a comment by explaining:

- a workaround or hack, and what it works around
- complexity that looks removable but is not, and what breaks if someone simplifies it
- a business or domain constraint that the code can't state on its own ("the vendor's free tier caps this at three")
- a limitation imposed by a downstream system, third-party API, or browser
- a deliberate tradeoff — a slower or uglier approach chosen for a reason
- a reference: spec section, documentation URL

Do not write:

- comments that restate the code, the function name, the types, or the signature
- narration of control flow, or a comment per step of an obvious sequence
- comments about the change itself: "changed to", "new", "previously", "now uses", "moved from", "as requested".
- comments addressed to the reviewer or to the person who asked for the change
- banner or divider comments, ASCII art, or section headers inside a file
- commented-out code. Delete it, unless it's for testing or is temporary in some other way and will be rolled back almost immediately.
- docblocks that only repeat what the type declarations already say.

Write comments that resist going stale:

- Comment the constraint, the decision, or the reason. Those outlive the implementation. Mechanics do not.
- Do not restate anything that lives in the code: names, values, counts, ordering, parameter lists. Each one is a copy that can drift out of sync.
- Attach a comment to the thing it explains, not to a line number or to code somewhere else in the file.
- When you change code, update or delete the comments that describe it.

Other rules:

- If a comment explains what code does, that's a naming problem. Rename the variable, rename the method, or extract a named collaborator instead.
- Keep comments to a sentence or two. Length does not add authority.
- Do not remove or rewrite an existing comment unless the code it describes changed. An unexplained comment may be recording something you can't see.
- The `// Arrange`, `// Act`, `// Assert` markers in tests are a required structural convention, not commentary. Keep them.
- Keep comments as close to the thing being commented on as possible. This helps reduce cognitive overhead.

## Architecture Rules

- Organize code by user flow and use case rather than by technical concern.
- Prefer co-location. UI, behavior, state, and feature-local helpers should live near the feature they serve.
- Optimize for locality of behavior. A developer should be able to understand or change a feature by reading a small, nearby cluster of files.
- Prefer file moves first and abstraction second.
- Prefer one small named object per workflow over one large manager.
- Prefer role-based names such as `Workflow`, `Coordinator`, `Navigator`, `Store`, `Factory`, `Resolver`, and `Builder`.
- Avoid `Type+Suffix.swift` filenames by default.
- Prefer file names that describe a role, feature slice, or user-visible responsibility rather than "an extension of X".
- Only use `+` filenames when extending a type is the clearest representation and the suffix names a narrow, concrete concern.
- Avoid vague suffixes such as `Actions`, `Content`, `Bindings`, `Operations`, or similar buckets when a more role-based name is available.
- Avoid vague buckets and vague names such as `Services`, `Managers`, `Helpers`, and `Utilities` unless there is a narrow, explicit reason.
- Keep extracted collaborators feature-local by default.
- Only move code into `Shared/` after at least two distinct flows clearly depend on it.
- When unsure between centralization and co-location, choose co-location.
- Do not normalize code into cross-cutting layers unless explicitly asked.
- When touching a large file, prefer extracting feature-local collaborators over extending the file further.
- Optimize for boundary clarity and maintainability over deduplication. Do not introduce shared abstractions for incidental duplication.

## Reference Shape

- No feature folder has been named as the reference example yet. Once one clearly shows the preferred structure, name it here. The target shape:
  - thin top-level view composition
  - feature-local workflows and coordinators
  - nearby state and supporting objects
  - small named collaborators with clear user-visible responsibilities

## Git

Do not stage, commit, push, or run any destructive git commands without explicit instruction. Reading git state (status, log, diff) is fine.

The user may intentionally stage acceptable work before asking for further changes. Do not treat staged changes as a problem, and do not unstage files unless explicitly asked. When reporting repo state, distinguish staged and unstaged changes only if it matters for the task.

## Public Repository

This repo will be public. Never commit secrets (signing certificates, notarization credentials, the Sparkle private key, the license server's signing key or Paddle credentials); read them from the Keychain or environment variables. Write code, comments, commit messages, plans and docs with a public audience in mind.

## Build Quality

The project is macOS only and must build with zero warnings.

The Xcode `BuildProject` MCP tool builds whichever scheme and destination Xcode currently has selected, so do not rely on it. Before reporting work as complete, run `xcodebuild` from the command line:

- `xcodebuild -project "Locus Git Gui.xcodeproj" -scheme "Locus Git Gui" -destination "platform=macOS" -configuration Debug build`

Check the build log at warning severity and fix any warnings (including SwiftLint violations) before declaring work done.

A clean build is not evidence that anything works. Launching the app and looking at it is, with one exception: **anything touching a permission, an entitlement, or how macOS registers the app has to be tested with `Scripts/install-test-build.sh`.** macOS attributes a permission to the process responsible for launching the app, so a build started from a terminal inherits the terminal's own grants and appears to work. For this app that covers the prompts for repositories in Documents, Desktop, Downloads, and on external or network volumes; iCloud key-value storage, which needs the Developer ID provisioning profile; the URL scheme the checkout hands back to; opening folders dropped on the Dock icon; and Sparkle updates.

## Tests

`Locus Git Gui Tests` does not run inside the app, because a hosted test run would launch it, start Sparkle, restore repository windows and show the setup checklist. It compiles only the app files it tests. To put another app file under test, add it to the "Locus Git Gui Tests" target membership (the membership exception set on the `LocusGitGui` folder in `project.pbxproj`). Only pure, `nonisolated` code with no dependencies on the rest of the app belongs there.

Run the tests with:

- `xcodebuild -project "Locus Git Gui.xcodeproj" -scheme "Locus Git Gui" -destination "platform=macOS" test`

## Reading the app's log

Read the app's log with:

- `log show --last 30m --predicate 'subsystem == "com.buzzingpixel.LocusGitGui"' --info`

`--info` is required. Entries logged at info level are silently left out of a plain `log show`, which looks exactly like an app that logged nothing. Use `log stream` with the same predicate to watch live.

This log is separate from the in-app Git log (View > Show Git Log), which records the commands run in a repository for the person using the app. Log decisions, kinds, counts and durations here, never repository paths, file names, branch names, commit messages or remote URLs. They carry people's names and private project names, and a remote URL can carry a password or token. `os_log` redacts interpolated strings unless marked `privacy: .public`, so such a value either leaks or shows as `<private>`.

## Swift 6 Concurrency

The project uses Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. App code is main-actor-isolated by default; opt out only when needed.

- **Pure value types** (enums, simple structs/classes with no isolated dependencies) may be marked `nonisolated` so they remain callable from any actor.
- **Prefer fixing call sites over widening `nonisolated` surface.** When a concurrency error pops up, first ask whether the calling code should be on the main actor; reach for `nonisolated` only when the type truly has no actor affinity.
- **`nonisolated(unsafe)` requires a justification.** Every use must have a comment explaining why the safety claim holds, and must suppress the `nonisolated_unsafe` SwiftLint rule via `// swiftlint:disable:next nonisolated_unsafe`. The justification must describe what enforces single-threaded access (e.g. "callback fires on main thread", "value handed straight to continuation and never aliased").
- **Prefer Sendable-by-construction over `nonisolated(unsafe)`.** When wrapping callback APIs in `withCheckedContinuation`, do type conversion inside the callback so the wrapper returns a Sendable concrete type instead of a non-Sendable opaque one.
- **Prefer async sequence APIs over manual observer registration** for NotificationCenter and similar callback patterns. The `notifications(named:)` + `compactMap` + `for await` pattern eliminates manual teardown and the associated isolation gymnastics.

## Color and Dark Mode

- When writing or adjusting colors, always consider both light and dark mode. Reason about both before reporting work as complete.
- Prefer system semantic colors (`Color(nsColor: .textBackgroundColor)`, `.windowBackgroundColor`, `.separatorColor`, `.controlBackgroundColor`, `.labelColor`, `.secondaryLabelColor`, etc.) over literal RGB values — they adapt automatically.
- For custom brand or themed colors, define them in `Assets.xcassets` with explicit Light and Dark variants, not as inline `Color(red: …)` literals.
- Never use bare `.white` / `.black` / hard-coded RGB for backgrounds, panels, borders, or strokes. Those stay the same in dark mode and look broken.
- When fixing or adjusting one color in a view, audit nearby colors in the same view. If one was hard-coded, the rest probably are too.

## Review Standard

Before closing work, self-check against:

- `Architecture/README.md`
- `Architecture/ReviewChecklist.md`
