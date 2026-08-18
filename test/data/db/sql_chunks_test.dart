import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/sql_chunks.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  group('sqlChunks', () {
    test('a list under the limit is one chunk', () {
      final chunks = sqlChunks(List.generate(10, (i) => i)).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single, hasLength(10));
    });

    test('exactly the limit is still one chunk', () {
      final chunks = sqlChunks(
        List.generate(kSqlVariableLimit, (i) => i),
      ).toList();
      expect(chunks, hasLength(1));
    });

    test('splits at the limit and loses nothing', () {
      final values = List.generate(kSqlVariableLimit * 2 + 7, (i) => i);

      final chunks = sqlChunks(values).toList();

      expect(chunks, hasLength(3));
      expect(chunks[0], hasLength(kSqlVariableLimit));
      expect(chunks[1], hasLength(kSqlVariableLimit));
      expect(chunks[2], hasLength(7));
      expect(chunks.expand((c) => c).toList(), values, reason: 'order kept');
    });

    // The DAOs keep their own early return; a zero-chunk iteration and an
    // `IN ()` are different problems.
    test('an empty list is no chunks', () {
      expect(sqlChunks(const <int>[]), isEmpty);
    });
  });

  // The reason the helper exists. SQLite caps bound parameters per statement at
  // 999 before 3.32, and sqflite uses Android's *system* SQLite — API 30 ships
  // 3.28. A collection past a thousand distinct cards was reaching
  // `getByPasscodes` with the whole list and would have thrown there.
  group('a dynamic-IN DAO method past the parameter limit', () {
    late Database db;

    setUp(() async {
      db = await openInMemoryTestDb();
    });

    tearDown(() async {
      await db.close();
    });

    test('reads back every row', () async {
      final dao = CardDao(db);
      final cards = [
        for (var i = 0; i < 1200; i++)
          YgoCard(
            passcode: (10000000 + i).toString(),
            name: 'Card $i',
          ),
      ];
      await dao.insertAll(cards);

      final read = await dao.getByPasscodes([
        for (final card in cards) card.passcode,
      ]);

      expect(read, hasLength(1200));
    });
  });
}
