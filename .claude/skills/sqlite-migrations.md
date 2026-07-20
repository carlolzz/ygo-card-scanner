# SQLite Migrations

Rules for evolving the schema.

- Once a migration version is committed, it is immutable. Fix mistakes by adding version N+1, never by editing N.
- Migrations live in `data/db/migrations.dart` as an ordered map of version → list of SQL statements. `onCreate` runs the full set; `onUpgrade` runs the tail from the current version.
- `PRAGMA foreign_keys = ON` on every open, in `onConfigure` — not `onOpen`, and never inside a transaction.
- Mirror the version into the `meta` table alongside sqflite's own `user_version` so the value is inspectable when debugging a user's exported database.
- SQLite cannot drop or retype a column. Changing one means: create the new table, copy, drop the old, rename. Write it out; do not attempt `ALTER COLUMN`.
- Every migration ships with a test that builds a v1 database, populates representative rows, upgrades to the current version, and asserts the data survived. An upgrade path with no test is not done.
- Adding an index is a migration too.
