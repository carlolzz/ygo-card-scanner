/// Splitting a dynamic-`IN` argument list so it cannot exceed SQLite's bound
/// parameter limit.
///
/// The convention set in step 17 builds `IN (?, ?, …)` placeholders from the
/// argument's **length**, which keeps the query parameterized but says nothing
/// about how long that list may be. SQLite caps bound parameters per statement
/// at `SQLITE_MAX_VARIABLE_NUMBER`: **999** before 3.32, 32766 from 3.32
/// onwards. sqflite uses Android's *system* SQLite, and API 30 ships 3.28 — so
/// on a phone that is still perfectly current, the thousandth distinct card in
/// a collection turns a valuation, a CSV import or a bulk delete into a hard
/// failure.
///
/// The split lives here, applied inside the DAO methods themselves, because a
/// caller cannot be expected to remember a limit it cannot see. Every affected
/// method reads the same helper and documents that it chunks.
library;

/// Most bound parameters allowed in one statement.
///
/// 900 rather than 999: it stays under the oldest limit worth supporting while
/// leaving headroom for the handful of extra `whereArgs` a method may add
/// beside its `IN` list, and it is a named constant rather than the kind of
/// bare number that gets tuned by guesswork.
const int kSqlVariableLimit = 900;

/// [values] in consecutive slices of at most [kSqlVariableLimit].
///
/// Empty in, empty out — callers keep their own early return, since a slice
/// count of zero and an `IN ()` are different problems.
Iterable<List<T>> sqlChunks<T>(List<T> values) sync* {
  for (var i = 0; i < values.length; i += kSqlVariableLimit) {
    final end = i + kSqlVariableLimit;
    yield values.sublist(i, end < values.length ? end : values.length);
  }
}
