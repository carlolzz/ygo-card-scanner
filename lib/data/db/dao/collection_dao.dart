import 'package:sqflite/sqflite.dart';

import '../../../models/card_condition.dart';
import '../../../models/card_edition.dart';
import '../../../models/collection_entry.dart';
import '../../../models/collection_entry_with_card.dart';

enum CollectionSortBy { name, dateAdded, quantity }

/// A rarity selection for the collection list: either a specific
/// `printings.rarity` value, or "no rarity at all".
///
/// The second case exists because a card logged without a printing (every
/// scanned quick-log that skipped the set picker) carries no rarity, so it can
/// never match a rarity value and would otherwise be reachable only under
/// "All". Its predicate is `p.rarity IS NULL` over the existing LEFT JOIN,
/// which is also exactly what [CollectionDao.rarityFilterOptions] reports as a
/// null option — so the chips and the filter agree by construction.
class RarityFilter {
  const RarityFilter.value(String this.rarity);
  const RarityFilter.noRarity() : rarity = null;

  /// The rarity to match, or null for "no rarity".
  final String? rarity;

  bool get isNoRarity => rarity == null;

  @override
  bool operator ==(Object other) =>
      other is RarityFilter && other.rarity == rarity;

  @override
  int get hashCode => rarity.hashCode;

  @override
  String toString() => 'RarityFilter(${rarity ?? 'none'})';
}

class CollectionFilter {
  const CollectionFilter({
    this.nameQuery,
    this.cardType,
    this.condition,
    this.rarity,
    this.sortBy = CollectionSortBy.name,
    this.sortDescending = false,
  });

  final String? nameQuery;
  final String? cardType;
  final CardCondition? condition;

  /// Null means no rarity filter at all — see [RarityFilter].
  final RarityFilter? rarity;

  final CollectionSortBy sortBy;
  final bool sortDescending;
}

class CollectionDao {
  const CollectionDao(this._db);

  final Database _db;

  /// Inserts a new entry, or increments `quantity` on an existing one
  /// matching (passcode, printingId, condition, edition, language).
  ///
  /// SQLite treats every NULL as distinct under a UNIQUE constraint, so
  /// `ON CONFLICT` never fires when `printingId` is null (a common case —
  /// manual add without picking a printing). That case is handled with an
  /// explicit find-or-insert instead of relying on the upsert.
  Future<CollectionEntry> addOrIncrement(CollectionEntry entry) {
    return _db.transaction((txn) async {
      if (entry.printingId != null) {
        await txn.rawInsert(
          '''
          INSERT INTO collection_entries
            (passcode, printing_id, condition, edition, language,
             quantity, notes, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(passcode, printing_id, condition, edition, language)
          DO UPDATE SET
            quantity = quantity + excluded.quantity,
            updated_at = excluded.updated_at
          ''',
          [
            entry.passcode,
            entry.printingId,
            entry.condition.toDb(),
            entry.edition.toDb(),
            entry.language,
            entry.quantity,
            entry.notes,
            entry.createdAt,
            entry.updatedAt,
          ],
        );
      } else {
        final existing = await txn.query(
          'collection_entries',
          where:
              'passcode = ? AND printing_id IS NULL '
              'AND condition = ? AND edition = ? AND language = ?',
          whereArgs: [
            entry.passcode,
            entry.condition.toDb(),
            entry.edition.toDb(),
            entry.language,
          ],
        );
        if (existing.isEmpty) {
          await txn.insert('collection_entries', entry.toMap());
        } else {
          final row = existing.first;
          await txn.update(
            'collection_entries',
            {
              'quantity': (row['quantity']! as int) + entry.quantity,
              'updated_at': entry.updatedAt,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }

      final result = await txn.query(
        'collection_entries',
        where: entry.printingId != null
            ? 'passcode = ? AND printing_id = ? AND condition = ? AND edition = ? AND language = ?'
            : 'passcode = ? AND printing_id IS NULL AND condition = ? AND edition = ? AND language = ?',
        whereArgs: entry.printingId != null
            ? [
                entry.passcode,
                entry.printingId,
                entry.condition.toDb(),
                entry.edition.toDb(),
                entry.language,
              ]
            : [
                entry.passcode,
                entry.condition.toDb(),
                entry.edition.toDb(),
                entry.language,
              ],
      );
      return CollectionEntry.fromMap(result.first);
    });
  }

  /// Sets the quantity of the entry with the given id. Deletes the row if
  /// [quantity] reaches 0.
  Future<void> setQuantity(int id, int quantity) async {
    if (quantity <= 0) {
      await _db.delete(
        'collection_entries',
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    await _db.update(
      'collection_entries',
      {'quantity': quantity},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> decrement(int id) async {
    final rows = await _db.query(
      'collection_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final quantity = rows.first['quantity']! as int;
    await setQuantity(id, quantity - 1);
  }

  Future<void> delete(int id) async {
    await _db.delete('collection_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Edits the entry [id]'s printing/condition/edition/language in place. If the
  /// new combination collides with a *different* existing entry for the same
  /// card (the same `collection_entries` UNIQUE key), the two are **merged**:
  /// the other entry absorbs this one's quantity and this row is deleted, so the
  /// list never shows two rows that are identical in every graded respect.
  ///
  /// Returns the id of the surviving entry — the same [id] on a plain edit, or
  /// the absorbing entry's id on a merge (so the caller can tell them apart).
  ///
  /// Mirrors [addOrIncrement]'s handling of a null [printingId]: SQLite treats
  /// every NULL as distinct under a UNIQUE constraint, so the collision lookup
  /// must use `printing_id IS NULL` rather than `printing_id = NULL`.
  Future<int> updateEntryDetails(
    int id, {
    required int? printingId,
    required CardCondition condition,
    required CardEdition edition,
    required String language,
  }) {
    return _db.transaction((txn) async {
      final current = await txn.query(
        'collection_entries',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty) return id;
      final passcode = current.first['passcode']! as String;
      final quantity = current.first['quantity']! as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      final collision = await txn.query(
        'collection_entries',
        where: printingId != null
            ? 'id != ? AND passcode = ? AND printing_id = ? '
                  'AND condition = ? AND edition = ? AND language = ?'
            : 'id != ? AND passcode = ? AND printing_id IS NULL '
                  'AND condition = ? AND edition = ? AND language = ?',
        whereArgs: printingId != null
            ? [id, passcode, printingId, condition.toDb(), edition.toDb(), language]
            : [id, passcode, condition.toDb(), edition.toDb(), language],
        limit: 1,
      );

      if (collision.isEmpty) {
        await txn.update(
          'collection_entries',
          {
            'printing_id': printingId,
            'condition': condition.toDb(),
            'edition': edition.toDb(),
            'language': language,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }

      final survivorId = collision.first['id']! as int;
      await txn.update(
        'collection_entries',
        {
          'quantity': (collision.first['quantity']! as int) + quantity,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [survivorId],
      );
      await txn.delete('collection_entries', where: 'id = ?', whereArgs: [id]);
      return survivorId;
    });
  }

  Future<List<CollectionEntryWithCard>> getAll({
    CollectionFilter filter = const CollectionFilter(),
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (filter.nameQuery != null && filter.nameQuery!.isNotEmpty) {
      conditions.add('c.name LIKE ?');
      args.add('%${filter.nameQuery}%');
    }
    if (filter.cardType != null) {
      conditions.add('c.type = ?');
      args.add(filter.cardType);
    }
    if (filter.condition != null) {
      conditions.add('ce.condition = ?');
      args.add(filter.condition!.toDb());
    }
    // Rarity comes off the LEFT JOIN below, so "no rarity" naturally covers
    // both an entry with no printing and a printing with no recorded rarity.
    final rarity = filter.rarity;
    if (rarity != null) {
      if (rarity.isNoRarity) {
        conditions.add('p.rarity IS NULL');
      } else {
        conditions.add('p.rarity = ?');
        args.add(rarity.rarity);
      }
    }

    final where = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';
    final orderColumn = switch (filter.sortBy) {
      CollectionSortBy.name => 'c.name',
      CollectionSortBy.dateAdded => 'ce.created_at',
      CollectionSortBy.quantity => 'ce.quantity',
    };
    final direction = filter.sortDescending ? 'DESC' : 'ASC';

    final rows = await _db.rawQuery('''
      SELECT
        ce.*,
        c.name AS card_name,
        c.type AS card_type,
        c.frame_type AS card_frame_type,
        c.attribute AS card_attribute,
        c.race AS card_race,
        c.atk AS card_atk,
        c.def AS card_def,
        c.level AS card_level,
        c.description AS card_description,
        c.image_url AS card_image_url,
        c.local_image_path AS card_local_image_path,
        c.archetype AS card_archetype,
        p.set_code AS printing_set_code,
        p.set_name AS printing_set_name,
        p.rarity AS printing_rarity
      FROM collection_entries ce
      JOIN cards c ON c.passcode = ce.passcode
      LEFT JOIN printings p ON p.id = ce.printing_id
      $where
      ORDER BY $orderColumn $direction
    ''', args);

    return rows.map(CollectionEntryWithCard.fromRow).toList();
  }

  /// The rarity values present in the collection, for the filter row's chips.
  ///
  /// A **null element** means "some entry has no rarity" — either it has no
  /// printing, or its printing records none. It appears only when such an entry
  /// exists, so the chip row never offers a dead option, and it is produced by
  /// the same `p.rarity IS NULL` shape [getAll] filters on.
  ///
  /// SQLite orders NULL first, so the no-rarity option leads the list.
  Future<List<String?>> rarityFilterOptions() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT p.rarity AS rarity
      FROM collection_entries ce
      LEFT JOIN printings p ON p.id = ce.printing_id
      ORDER BY p.rarity
    ''');
    return [for (final row in rows) row['rarity'] as String?];
  }

  Future<int> totalCardCount() async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS total FROM collection_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> distinctCardCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(DISTINCT passcode) AS total FROM collection_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total copies (summed quantity) grouped by [condition] db value, for the
  /// statistics screen. Keyed by the stored SCREAMING_SNAKE value.
  Future<Map<String, int>> sumByCondition() => _sumByColumn('condition');

  /// Total copies grouped by language code (e.g. `EN`, `DE`).
  Future<Map<String, int>> sumByLanguage() => _sumByColumn('language');

  /// A fixed, non-user-supplied column of `collection_entries` — safe to
  /// interpolate. NULLs are folded to the empty string.
  Future<Map<String, int>> _sumByColumn(String column) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE($column, \'\') AS k, SUM(quantity) AS n '
      'FROM collection_entries GROUP BY k',
    );
    return {
      for (final row in rows) row['k']! as String: row['n']! as int,
    };
  }

  /// Total copies grouped by the joined `cards.type` (Effect Monster / Spell
  /// Card / …). NULL types fold to the empty string.
  Future<Map<String, int>> sumByCardType() async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(c.type, '') AS k, SUM(ce.quantity) AS n
      FROM collection_entries ce
      JOIN cards c ON c.passcode = ce.passcode
      GROUP BY k
    ''');
    return {
      for (final row in rows) row['k']! as String: row['n']! as int,
    };
  }

  Future<List<CollectionEntry>> getEntriesForPasscode(String passcode) async {
    final rows = await _db.query(
      'collection_entries',
      where: 'passcode = ?',
      whereArgs: [passcode],
    );
    return rows.map(CollectionEntry.fromMap).toList();
  }
}
