import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/router.dart';
import 'package:ygo_scanner/data/db/database.dart';

/// Pumps the real app router with [db] wired in as the app database, via a
/// [ProviderScope] override. Shared by any widget test that needs to
/// navigate through real screens backed by a real (in-memory) database.
Future<void> pumpApp(WidgetTester tester, Database db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
      child: MaterialApp.router(routerConfig: buildAppRouter()),
    ),
  );
}

/// sqflite_common_ffi resolves queries via a background isolate. Plain
/// `tester.pump()` only advances fake time, which never gives that isolate
/// round trip a chance to complete — even inside `tester.runAsync()`, so
/// tests hang in the loading state indefinitely. Interleaving a real
/// `Future.delayed` between pumps lets the round trip actually finish.
Future<void> pumpUntilSettled(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
