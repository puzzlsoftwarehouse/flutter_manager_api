class UploadHeaders {
  UploadHeaders._();

  static const Set<String> _blockedHeaderKeys = <String>{
    'content-type',
    'content-length',
    'apiurl',
  };

  static Map<String, String> withoutContentType(Map<String, String>? headers) {
    return forMediaApi(headers);
  }

  static Map<String, String> forMediaApi(Map<String, String>? headers) {
    if (headers == null) {
      return <String, String>{};
    }

    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, String> entry in headers.entries) {
      if (_blockedHeaderKeys.contains(entry.key.toLowerCase())) {
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }
}
