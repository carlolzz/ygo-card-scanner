/// Route path constants. Kept import-free so both the router and feature
/// screens can depend on it without creating an import cycle.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String scan = '/scan';
  static const String collection = '/collection';
  static const String collectionDetail = '/collection/detail';
  static const String statistics = '/statistics';
  static const String settings = '/settings';
}
