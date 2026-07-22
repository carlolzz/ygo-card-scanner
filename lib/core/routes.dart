/// Route path constants. Kept import-free so both the router and feature
/// screens can depend on it without creating an import cycle.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String scan = '/scan';

  /// Manual search-and-add wizard. A permanent first-class alternative to
  /// scanning (reached from the scan screen's toolbar and its OCR-miss
  /// fallback), not a sub-route of it.
  static const String addCard = '/add-card';
  static const String collection = '/collection';
  static const String collectionDetail = '/collection/detail';
  static const String statistics = '/statistics';
  static const String settings = '/settings';
}
