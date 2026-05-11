import 'dart:convert';

bool webSocketIncomingIsPong(String raw) {
  final String trimmed = raw.trim();

  if (trimmed == '{"type":"pong"}') {
    return true;
  }

  if (!trimmed.contains('pong')) {
    return false;
  }

  try {
    final dynamic decoded = jsonDecode(trimmed);

    if (decoded is! Map) {
      return false;
    }

    final Map<dynamic, dynamic> map = decoded;

    return map['type'] == 'pong';
  } catch (_) {
    return false;
  }
}
