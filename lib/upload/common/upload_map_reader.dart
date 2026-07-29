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

  static int? readInt(Map<String, dynamic> source, String key) {
    final Object? value = source[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static int readRequiredInt(Map<String, dynamic> source, String key) {
    final int? value = readInt(source, key);
    if (value == null) {
      throw ArgumentError('Missing required parameter: $key');
    }
    return value;
  }

  static String readRequiredString(Map<String, dynamic> source, String key) {
    final String? value = readString(source, key);
    if (value == null) {
      throw ArgumentError('Missing required parameter: $key');
    }
    return value;
  }

  static bool readBool(
    Map<String, dynamic> source,
    String key, {
    bool fallback = false,
  }) {
    final Object? value = source[key];
    if (value == null) {
      return fallback;
    }
    if (value is bool) {
      return value;
    }
    final String text = value.toString().toLowerCase();
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    return fallback;
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
