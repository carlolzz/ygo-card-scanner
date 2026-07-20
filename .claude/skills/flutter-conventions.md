# Flutter Conventions

House style. Apply to all Dart code in this repo.

- Files are snake_case.dart. One public class per file unless the types are trivially coupled (enum + its extension).
- Riverpod: providers are named `<thing>Provider` and live next to what they provide. Repositories get plain `Provider`, async reads get `FutureProvider`, mutable screen state gets `NotifierProvider`. No `StateProvider` for anything with more than one field.
- UI consumes async state through `AsyncValue.when` — every screen renders explicit loading and error branches. No silent empty states standing in for failures.
- No `setState` in `features/`. No `BuildContext` stored in fields.
- No business logic in `build()`. Widgets read providers and render; decisions happen in notifiers and repositories.
- freezed/json_serializable part files sit beside their source. Regenerate with `dart run build_runner build --delete-conflicting-outputs`.
- Errors cross layer boundaries as typed failures via `core/result.dart`, not raw exceptions escaping the data layer.
- Every user-visible string goes through a single constants file for now, so localization is a refactor and not a rewrite.
- `flutter analyze` must be clean before any session ends. Warnings are errors.
