part of 'package:manager_api/manager_api.dart';

abstract final class _RequestLogFormatting {
  _RequestLogFormatting._();

  static const int variablesMaxLength =
      int.fromEnvironment('REQUESTLOGGER_VARS_MAX', defaultValue: 0);

  static const int _latencyColumnWidth = 8;

  static const int _typeColumnWidth = 8;

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
