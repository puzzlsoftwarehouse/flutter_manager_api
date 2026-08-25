part of 'package:manager_api/manager_api.dart';

abstract final class _RequestLogPalette {
  _RequestLogPalette._();

  static Color _severity({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
  }) {
    if (isAlert) {
      return const Color(0xFFFFD54F);
    }
    if (isError) {
      return const Color(0xFFFF5252);
    }
    if (isCanceled) {
      return const Color(0xFF90A4AE);
    }
    return const Color(0xFFFFC107);
  }

  static Color latency(int elapsedMs) {
    if (elapsedMs < 250) {
      return const Color(0xFF69F0AE);
    }
    if (elapsedMs < 600) {
      return const Color(0xFF9CCC65);
    }
    if (elapsedMs < 1200) {
      return const Color(0xFFFFD54F);
    }
    if (elapsedMs < 2500) {
      return const Color(0xFFFF8A65);
    }
    return const Color(0xFFFF1744);
  }

  static Color resolveAccent({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
    required bool neutralStyle,
    required int? latencyMs,
  }) {
    if (neutralStyle) {
      return const Color(0xFF607D8B);
    }

    if (isError || isAlert || isCanceled) {
      return _severity(
        isError: isError,
        isAlert: isAlert,
        isCanceled: isCanceled,
      );
    }

    if (latencyMs != null) {
      return latency(latencyMs);
    }

    return const Color(0xFF4FC3F7);
  }
}
