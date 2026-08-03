/// The one rule every "type to narrow a list" box in the app follows.
///
/// Every whitespace-separated term in [query] must appear somewhere in
/// [haystack], case-insensitively and in any order — so "raiders super" finds
/// "MRD-EN094 · Metal Raiders · Super Rare", and a set code typed with or
/// without its language block still matches. An empty or blank query matches
/// everything rather than nothing: these boxes start as a plain list the user
/// can scroll, and typing only ever narrows it.
///
/// Lives here rather than beside any one caller because it is now shared by the
/// printing pickers (scan review gate, manual add wizard, collection edit sheet)
/// and the collection filter sheet's set box. Two copies of a filter rule drift
/// silently — one box would quietly match differently from the next.
bool matchesSearchTerms(String haystack, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((term) => term.isEmpty);
  if (terms.isEmpty) return true;
  final lower = haystack.toLowerCase();
  return terms.every(lower.contains);
}
