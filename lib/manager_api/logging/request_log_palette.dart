part of 'package:manager_api/manager_api.dart';

abstract final class _RequestLogPalette {
  _RequestLogPalette._();

  static Color _severity({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
  }) {
    if (isAlert) return Colors.yellowAccent;
    if (isError) return const Color(0xFFE57373);
    if (isCanceled) return Colors.white70;
    return Colors.amber;
  }

  static Color latency(int elapsedMs) {
    const Color greenFast = Color(0xFF69F0AE);
    const Color strongRed = Color(0xFFD32F2F);

    if (elapsedMs >= 2000) {
      return strongRed;
    }

    final double t = (elapsedMs / 2000).clamp(0.0, 1.0);

    if (t <= 0.5) {
      return Color.lerp(greenFast, Colors.amber.shade400, t * 2)!;
    }

    return Color.lerp(Colors.amber.shade700, Colors.red.shade400, (t - 0.5) * 2)!;
  }

  static Color resolveAccent({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
    required bool neutralStyle,
    required int? latencyMs,
  }) {
    if (neutralStyle) {
      return Colors.blueGrey.shade600;
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

    return Colors.amber;
  }
}
