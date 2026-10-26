import 'package:flutter/foundation.dart';

typedef UploadResilienceLogEventListener = void Function(
    String event, Map<String, Object?> details);

abstract final class UploadResilienceLog {
  static UploadResilienceLogEventListener? eventListener;

  static bool get enabled {
    const bool fromEnvironment = bool.fromEnvironment('UPLOAD_RESILIENCE_LOG');
    return fromEnvironment || kDebugMode;
  }

  static void log(String message) {
    if (!enabled) {
      return;
    }
    debugPrint('[UploadResilience] $message');
  }

  static void logEvent(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    eventListener?.call(event, details);
    if (!enabled) {
      return;
    }
    if (details.isEmpty) {
      debugPrint('[UploadResilience] $event');
      return;
    }
    final StringBuffer buffer = StringBuffer('[UploadResilience] $event');
    for (final MapEntry<String, Object?> entry in details.entries) {
      buffer.write(' | ${entry.key}=${entry.value}');
    }
    debugPrint(buffer.toString());
  }
}
