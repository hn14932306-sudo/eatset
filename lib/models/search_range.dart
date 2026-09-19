/// How far from the user a restaurant may be. Distances are straight-line, the
/// same figure the cards show, so the wording never implies a walking route.
class SearchRange {
  SearchRange._();

  /// Metres. The backend accepts 100-2000.
  static const options = [500, 800, 1200, 2000];
  static const defaultMeters = 1200;

  static String label(int meters) {
    if (meters < 1000) return '$meters 公尺';
    final km = meters / 1000;
    return '${km == km.roundToDouble() ? km.round() : km} 公里';
  }

  /// Anything stored or received that is not a known option falls back to the
  /// default rather than reaching the backend.
  static int normalize(Object? value) =>
      value is int && options.contains(value) ? value : defaultMeters;
}
