class UploadMapReader {
  UploadMapReader._();

  static String? readString(Map<String, dynamic> source, String key) {
    final Object? value = source[key];
    if (value == null) {
      return null;
    }
    final String text = value.toString();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  static Map<String, dynamic> asStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
