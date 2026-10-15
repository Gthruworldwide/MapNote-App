# MapNote — Agent Instructions

MapNote is an **offline-first** Flutter saved-places app (optional Google Drive
backup, opt-in Gemini "Smart Insights"). The full, pass/fail evaluation
standards for every area of the codebase live in
[AGENT_SKILLS.md](AGENT_SKILLS.md) — **read it before editing and before
finishing any task**.

## Non-negotiables (summary)

1. Always run `flutter analyze` and `flutter test` after making code modifications.
2. Do not break existing Hive CE data structures or change database schemas without backward compatibility.
3. Ensure all user-facing strings are localized using `app_en.arb` and `app_ar.arb`.
4. State management must follow the Riverpod standards already defined in `app_providers.dart`.
5. Any new location/sensor stream must properly handle mounted checks and unsubscribe on dispose.

> When in doubt, [AGENT_SKILLS.md](AGENT_SKILLS.md) wins. Report per-area
> pass/fail with evidence per the "Reporting" section there.
