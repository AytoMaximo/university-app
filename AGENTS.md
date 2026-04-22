# Agent Context For This Fork

This fork is `AytoMaximo/university-app`. The upstream repository is
`0niel/university-app`.

## Goal

This fork currently exists to publish a standalone web application with only the
university map and local classroom search. Keep the implementation inside this
repository instead of copying map code into a separate project, so future
upstream map/assets updates can still be merged.

## Current Production

- Public URL to use for checks: `https://university-app-taupe.vercel.app/`
- Custom domain also points at the same Vercel project: `https://map.aytomaximo.ru/`
- Vercel team slug: `aytomaximo-projects`
- Vercel project: `university-app`
- Pushing `master` to `origin` triggers the Vercel production deployment.
- The Vercel build command is `bash tools/vercel_build_flutter_web.sh`.

Use the public alias URLs for browser checks. Direct deployment URLs can require
Vercel authentication.

## What Has Been Implemented

- `lib/main/main_map_web.dart` starts the standalone web app.
- `lib/map/view/map_page_view.dart` is reusable by the main app and standalone
  app. For standalone use it receives an empty selected-room action instead of
  routing to schedule search.
- `lib/map/config/map_campuses.dart` is the shared map campus/floor config.
- `lib/map/bloc/map_bloc.dart` builds local search entries from SVG objects and
  handles room selection from search.
- `lib/map/services/map_room_search_service.dart` normalizes and filters local
  room search queries without backend/API calls.
- `lib/map/widgets/svg_interactive_view.dart` accepts an external
  `selectedRoomId`, centers the selected room, highlights it, and pulses the
  highlight after search focus.

Important commits:

- `f48eb94d feat: add standalone university map web app`
- `fa11639b fix(map): keep room search selection active`

## Expected Map Search Behavior

When a user searches for a classroom and selects a result:

- switch to the result campus and floor;
- center the map camera on the room;
- highlight and pulse the selected room;
- show the selected-room panel;
- do not navigate to the schedule page in standalone mode.

Manual tapping on a room should still select it and show the selected-room panel.

The search is intentionally local-only. Do not add `ScheduleRepository`, API,
Firebase, Supabase, Sentry, ads, NFC, or the main navigation shell to the
standalone map MVP unless the user explicitly asks for it.

## Build And Validation

Pinned Flutter version is `3.38.9` from `.fvmrc`. On this Windows machine,
`flutter` may be missing from PATH; use:

```powershell
D:\Flutter\bin\flutter.bat --version
```

Preferred quick validation after map changes:

```powershell
D:\Flutter\bin\dart.bat format lib\map lib\main\main_map_web.dart
D:\Flutter\bin\dart.bat analyze lib\map lib\main\main_map_web.dart
```

Standalone production build:

```powershell
D:\Flutter\bin\flutter.bat build web --release --target lib\main\main_map_web.dart
```

Vercel uses a slimmer build path:

```bash
bash tools/vercel_build_flutter_web.sh
```

That script temporarily copies `tools/pubspec_map_web.yaml` over `pubspec.yaml`
inside the Vercel build environment, removes `pubspec.lock`, runs `flutter pub
get`, then builds `lib/main/main_map_web.dart`.

## Local Windows Build Notes

The full repository `pubspec.yaml` currently has dependency and workspace
complexity that can break local web builds on Windows:

- `share_plus` can be resolved with an incompatible
  `share_plus_platform_interface` override when using the full app pubspec;
- Flutter may fail to create Windows plugin symlinks with `ERROR_INVALID_FUNCTION`;
- stale `.dart_tool/flutter_build/**/web_plugin_registrant.dart` can keep old
  full-app web plugins after switching to the slim map pubspec.

For local standalone build troubleshooting:

- do not commit temporary `pubspec.yaml` or `pubspec.lock` changes from using
  `tools/pubspec_map_web.yaml`;
- do not commit generated `build/web`, `.dart_tool`, or accidental l10n
  regeneration unless that is the requested change;
- if a build uses a stale web plugin registrant, remove only generated
  `.dart_tool/flutter_build` and rebuild;
- if Flutter creates unrelated tracked changes while validating, restore only
  those unrelated generated files.

## Coding And Workflow Rules

- Keep changes minimal and scoped to the standalone map/search/deploy task.
- Prefer existing Flutter/Dart patterns in this repository.
- Code comments must be Russian only.
- Avoid new abstractions unless they remove real duplication or match existing
  local patterns.
- Do not revert unrelated user changes.
- Use `rg` for search.
- Use non-interactive git commands.
- Run the smallest relevant real validation after code changes.
- For web UI changes, verify with a browser when practical.

