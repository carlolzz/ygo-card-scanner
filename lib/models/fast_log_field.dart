/// A per-card detail that Fast log can stop asking about.
///
/// **Ticked means "still ask me"**, not "skip this". Anything not in
/// `AppSettings.fastLogFields` is written from its Settings default with no
/// control shown at all. The consequence is the rule on `AppSettings`: ticking
/// every member asks for everything, so Fast log changes nothing and is treated
/// as off.
///
/// The set/expansion is deliberately **not** a member. It is never asked while
/// Fast log is on: `preferredPrinting` still auto-picks a card's sole known
/// printing, and a card with several is logged without one.
///
/// [label] duplicates the three words that also appear in `AppStrings` as the
/// Defaults section's field labels. That is a decision, not an oversight, and
/// matches `CardEdition.label` / `CollectionViewMode.label`: a member's own name
/// belongs on the member, so a `for (final field in values)` loop can render
/// itself without a lookup table beside it.
///
/// Persisted by name (in the `meta` table, not a column), never by ordinal, so
/// the declaration order below is free to change. It is condition -> edition ->
/// language because every other list of these three in the app is: the Settings
/// Defaults section, `_ConditionStep`, and the scan review panel.
enum FastLogField {
  condition('Condition'),
  edition('Edition'),
  language('Language');

  const FastLogField(this.label);

  /// The field's name as it appears in the UI.
  final String label;

  String toDb() => switch (this) {
    FastLogField.condition => 'CONDITION',
    FastLogField.edition => 'EDITION',
    FastLogField.language => 'LANGUAGE',
  };

  static FastLogField fromDb(String value) => switch (value) {
    'CONDITION' => FastLogField.condition,
    'EDITION' => FastLogField.edition,
    'LANGUAGE' => FastLogField.language,
    _ => throw ArgumentError('Unknown FastLogField db value: $value'),
  };
}
