# Flutter Test Troubleshooting (Windows)

Failures and hangs hit repeatedly while running `flutter test`/`flutter analyze`
on this machine, and what actually fixed them. Check this before assuming a
code change broke something.

## "Flutter failed to delete file at build\native_assets\windows\sqlite3.dll"

Two distinct causes, same symptom:

- **A live `flutter run -d <device>` debug session is open.** It shares this
  project's `build/` directory with `flutter test`, and holds native asset
  files open for the duration of the run. Ask the user to stop it (or confirm
  they already have) before retrying — do not kill their live session
  yourself.
- **An orphaned test-runner process tree from a previously killed
  `flutter test` invocation.** Killing/stopping a background bash task that
  wraps `flutter test` does not reliably kill its child process tree on
  Windows — `cmd.exe → dart.exe → dartvm.exe → dartaotruntime.exe` and
  `flutter_tester.exe` can survive and keep the DLL locked.

Diagnose with:

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'dart|flutter_tester' } | Select-Object ProcessId, Name, ParentProcessId, CommandLine
```

Read the `CommandLine` column before touching anything — `language-server`,
`tooling-daemon`, `devtools`, and `... run -d <device>` entries are the IDE/
live debug session and must be left alone. A `... flutter.bat test ...` /
`flutter_tester.exe` entry with no corresponding live task of yours is the
orphan; kill that specific process tree:

```powershell
Stop-Process -Id <cmd_pid>,<dart_pid>,<dartvm_pid>,<dartaotruntime_pid>,<flutter_tester_pid> -Force
```

Never blanket-kill every `dart.exe`/`dartvm.exe` process — some are the IDE's
own language server/tooling daemon and killing them breaks the editor's
diagnostics feed for the rest of the session.

## sqflite_common_ffi `:memory:` opens can silently collide

`databaseFactoryFfi.openDatabase(inMemoryDatabasePath, ...)` defaults to
`singleInstance: true`. Opening a second in-memory database in the same test
(even through the same `openInMemoryTestDb()` helper) can hand back the
*same already-open, already-populated* connection instead of a fresh one —
this reads as a confusing correctness bug (counts/rows that shouldn't be
there) rather than an obvious "connection reused" error.

Fix: `test/data/db/test_db.dart`'s `openInMemoryTestDb()` passes
`singleInstance: false` for exactly this reason. Any one-off manual
`databaseFactoryFfi.openDatabase(inMemoryDatabasePath, ...)` call elsewhere
(e.g. a migration-upgrade test that needs to open the *same* path at two
different schema versions) needs the same override.

## `pumpAndSettle()` hangs forever on indeterminate spinners

A bare `CircularProgressIndicator()` (no `value:`) repeats its animation
forever. If one is anywhere in the widget tree — even in a state meant to be
on-screen for a single transitional frame — `pumpAndSettle()` never sees
"no more scheduled frames" and hangs until the test times out.

- Don't render an indeterminate spinner for a state that's expected to be
  transitional/instantaneous (e.g. a "success, about to be swapped away"
  state) — render nothing (`SizedBox.shrink()`) instead.
- For any screen that renders one deliberately (a real loading state), use
  bounded explicit `pump(duration)` loops in tests instead of
  `pumpAndSettle()`.

## Fake `Stream`s drain before a single frame renders

A test double stream with no delay between emitted values (e.g.
`Stream.fromIterable([a, b])`) can run to completion entirely within
microtasks before Flutter ever schedules a frame — the "intermediate" state
you meant to assert on is never actually rendered, and the test silently
observes the final state instead.

Fix: put a real `await Future.delayed(...)` between (and after) each emitted
test value, then advance with `tester.pump(duration)` matching that delay —
`pump(duration)` advances the fake clock and fires due timers, giving each
state its own frame to assert against.

## Open the ffi db in `setUp`, never inside a `testWidgets` body

`openInMemoryTestDb()` opens a `sqflite_common_ffi` connection via a background
isolate — a real-async operation. The body of a `testWidgets` callback runs in
the **fake-async zone**; awaiting the ffi open there appears to succeed but
leaves the isolate connection in a state that **hangs the whole test at
teardown** (the body and all assertions pass, the reporter just never advances
past `+N` to `+N+1`, and the test eventually dies on flutter's 10-minute
timeout). The hang is not in the widgets, the router mount, `runAsync`, or
`db.close()` — it is specifically the db having been *opened* in the fake-async
zone.

Fix: open the db in `setUp` (a real-async zone) and close it in `tearDown`,
exactly like the DAO and collection tests do. If a test needs to *write*
fixture rows before pumping (e.g. seeding an "already synced" db), do those
writes inside the `tester.runAsync()` block, not in the bare body.

```dart
late Database db;
setUp(() async { db = await openInMemoryTestDb(); });   // real-async: OK
tearDown(() async { await db.close(); });
// NOT: testWidgets('...', (tester) async { final db = await openInMemoryTestDb(); ... })
```

This was the true cause of `test/features/sync/app_gate_test.dart` hanging —
not the `MaterialApp(home:)` → `MaterialApp.router` gate swap, which works
fine once the db is opened in `setUp`.

## sqflite_common_ffi resolves queries via a background isolate

Plain `pump()`/`pumpAndSettle()` only advance fake time; they never give that
isolate round trip a chance to complete, even inside `tester.runAsync()`
alone. Wrap the interaction in `tester.runAsync()` *and* interleave real
`Future.delayed` yields with `tester.pump()` — see `pumpUntilSettled()` in
`test/support/widget_test_harness.dart`. Any widget test that resolves a
Riverpod provider backed by the real (even in-memory) database needs this,
not just ones hitting the on-device production DB.
