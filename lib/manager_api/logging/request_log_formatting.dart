part of 'package:manager_api/manager_api.dart';

abstract final class _RequestLogFormatting {
  _RequestLogFormatting._();

  static const int variablesMaxLength =
      int.fromEnvironment('REQUESTLOGGER_VARS_MAX', defaultValue: 0);

  static const int slowThresholdMs =
      int.fromEnvironment('REQUESTLOGGER_SLOW_MS', defaultValue: 1000);

  static const int _latencyColumnWidth = 8;

  static const int _typeColumnWidth = 8;

  static bool isSlow(int elapsedMs) =>
      slowThresholdMs > 0 && elapsedMs >= slowThresholdMs;

  static String statusIcon({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
    required int? latencyMs,
  }) {
    if (isError) {
      return '✕';
    }

    if (isCanceled) {
      return '⊘';
    }

    if (isAlert) {
      return '⚠';
    }

    if (latencyMs != null && isSlow(latencyMs)) {
      return '!';
    }

    return '✓';
  }

  static String requestLine({
    required String head,
    required String vars,
    required int? latencyMs,
    String suffix = '',
    int count = 1,
  }) {
    final String repeat = count > 1 ? ' ×$count' : '';

    return '${latencyColumn(latencyMs)}  $head$repeat  $vars$suffix';
  }

  static String formatElapsed(int elapsedMs) {
    if (elapsedMs < 1000) {
      return '${elapsedMs}ms';
    }

    return '${(elapsedMs / 1000).toStringAsFixed(2)}s';
  }

  static String latencyColumn(int? elapsedMs) {
    if (elapsedMs == null) {
      return ' ' * _latencyColumnWidth;
    }

    return formatElapsed(elapsedMs).padLeft(_latencyColumnWidth);
  }

  static String typeColumn(String type) {
    if (type.length >= _typeColumnWidth) {
      return type;
    }

    return type.padRight(_typeColumnWidth);
  }

  static String formatVariables(Map<String, dynamic> variables) {
    if (variables.isEmpty) {
      return '{}';
    }

    String encoded;

    try {
      encoded = jsonEncode(
        variables,
        toEncodable: (Object? value) => value.toString(),
      );
    } catch (_) {
      encoded = variables.toString();
    }

    if (variablesMaxLength <= 0 || encoded.length <= variablesMaxLength) {
      return encoded;
    }

    return '${encoded.substring(0, variablesMaxLength)}…';
  }

  static String compactName(String name, String? groupKey) {
    if (groupKey == null || groupKey.isEmpty || name == groupKey) {
      return name;
    }

    if (!name.startsWith('${groupKey}_')) {
      return name;
    }

    return '…${name.substring(groupKey.length)}';
  }

  static String graphqlBlockKey(String operationName) {
    final int underscoreIndex = operationName.indexOf('_');

    if (underscoreIndex <= 0) {
      return operationName;
    }

    return operationName.substring(0, underscoreIndex);
  }
}
