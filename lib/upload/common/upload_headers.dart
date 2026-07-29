class UploadHeaders {
  UploadHeaders._();

  static Map<String, String> withoutContentType(Map<String, String>? headers) {
    if (headers == null) {
      return <String, String>{};
    }

    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }
}
