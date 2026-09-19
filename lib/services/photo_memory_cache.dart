import 'dart:typed_data';

/// Short-lived, in-memory only. It exists so paging back, promoting an
/// alternative to the main card, or opening details never bills the same photo
/// twice in one sitting. Nothing is written to disk, and entries expire quickly:
/// Google restricts caching Places content, so keep this window small.
class PhotoMemoryCache {
  PhotoMemoryCache({
    this.maxEntries = 8,
    this.maxAge = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final PhotoMemoryCache shared = PhotoMemoryCache();

  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{}; // insertion-ordered

  Uint8List? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.at) > maxAge) return null;
    _entries[key] = entry; // most recently used goes last
    return entry.bytes;
  }

  bool contains(String key) {
    final entry = _entries[key];
    return entry != null && _now().difference(entry.at) <= maxAge;
  }

  void put(String key, Uint8List bytes) {
    _entries.remove(key);
    _entries[key] = _Entry(bytes, _now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(String key) => _entries.remove(key);
  void clear() => _entries.clear();
  int get length => _entries.length;
}

class _Entry {
  const _Entry(this.bytes, this.at);
  final Uint8List bytes;
  final DateTime at;
}
