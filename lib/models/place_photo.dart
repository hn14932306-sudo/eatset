/// Transient Places photo metadata. Never serialize photo resources or URLs into
/// preferences, favorites, or history: Google photo names can expire.
class PlacePhoto {
  const PlacePhoto({
    required this.name,
    this.token = '',
    this.authors = const [],
    this.sourceUri,
    this.reportUri,
  });

  final String name;
  final String token;
  final List<PhotoAuthor> authors;
  final Uri? sourceUri;
  final Uri? reportUri;

  static PlacePhoto? fromGoogle(Map<String, dynamic> json, String placeId) {
    final name = json['name'];
    if (name is! String) return null;
    final parts = name.split('/');
    if (parts.length != 4 ||
        parts[0] != 'places' ||
        parts[1] != placeId ||
        parts[2] != 'photos' ||
        parts[3].isEmpty) {
      return null;
    }
    final authors = <PhotoAuthor>[];
    for (final raw in (json['authorAttributions'] as List? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final label = raw['displayName'];
      if (label is! String || label.trim().isEmpty) continue;
      authors.add(PhotoAuthor(label, safePhotoLink(raw['uri'])));
    }
    return PlacePhoto(
      name: name,
      token: json['token'] as String? ?? '',
      authors: authors,
      sourceUri: safePhotoLink(json['googleMapsUri']),
      reportUri: safePhotoLink(json['flagContentUri']),
    );
  }
}

class PhotoAuthor {
  const PhotoAuthor(this.name, this.uri);
  final String name;
  final Uri? uri;
}

/// Metadata is external data, not HTML or executable links.
Uri? safePhotoLink(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}
