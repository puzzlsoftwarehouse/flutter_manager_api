part of 'package:manager_api/manager_api.dart';

abstract final class _RequestLogFormatting {
  _RequestLogFormatting._();

  static String formatElapsed(int elapsedMs) {
    final String secondsPart = (elapsedMs / 1000).toStringAsFixed(1);

    return '${elapsedMs}ms (${secondsPart}s)';
  }

  static String graphqlBlockKey(String operationName) {
    final int underscoreIndex = operationName.indexOf('_');

    if (underscoreIndex <= 0) {
      return operationName;
    }

    return operationName.substring(0, underscoreIndex);
  }
}
