import 'package:manager_api/models/graphql/graphql_result.dart';

class GraphQLErrorDetails {
  final String? code;
  final String? userMessage;
  final String? technicalLog;

  const GraphQLErrorDetails({
    this.code,
    this.userMessage,
    this.technicalLog,
  });
}

class RestErrorDetails {
  final String? code;
  final String? type;
  final String? userMessage;
  final String? technicalLog;

  const RestErrorDetails({
    this.code,
    this.type,
    this.userMessage,
    this.technicalLog,
  });

  bool get isNoConnection =>
      type == 'noConnection' ||
      FailureMessageResolver.matchesNoConnectionMessage(userMessage);

  bool get isTimeout => type == 'timeout' || userMessage == 'timeout';

  bool get isCancel =>
      type == 'cancel' ||
      code == 'cancel' ||
      FailureMessageResolver.matchesCancelMessage(userMessage);
}

class FailureMessageResolver {
  FailureMessageResolver._();

  static const int _defaultMaxLength = 180;

  static const Set<String> _internalCodes = <String>{
    'timeout',
    'noConnection',
    'cancelled',
    'cancel',
  };

  static GraphQLErrorDetails extractGraphQLErrorDetails(
    List<GraphQLError>? errors,
  ) {
    if (errors == null || errors.isEmpty) {
      return const GraphQLErrorDetails();
    }

    final GraphQLError firstError = errors.first;
    final Map<String, dynamic>? extensions = firstError.extensions;
    final String? code = _readCode(extensions, firstError.message);
    final String? userMessage = _readUserMessage(
      extensions: extensions,
      message: firstError.message,
    );
    final String technicalLog = errors
        .map((GraphQLError error) => _formatGraphQLError(error))
        .join('\n');

    return GraphQLErrorDetails(
      code: code,
      userMessage: userMessage,
      technicalLog: technicalLog,
    );
  }

  static RestErrorDetails extractRestErrorDetails(
    Map<String, dynamic> exception,
  ) {
    final String? type = exception['type']?.toString();
    final String? code = _normalizeText(
      exception['code']?.toString() ?? exception['exception_code']?.toString(),
    );
    final String? userMessage = _normalizeText(
      exception['message']?.toString() ??
          exception['detail']?.toString() ??
          exception['error']?.toString(),
    );
    final String? technicalLog = _normalizeText(exception.toString());

    return RestErrorDetails(
      code: code,
      type: type,
      userMessage: userMessage,
      technicalLog: technicalLog,
    );
  }

  static String extractLinkExceptionMessage(
    Object? exception, {
    required String fallback,
  }) {
    if (exception == null) {
      return fallback;
    }

    final String raw = exception.toString().toLowerCase();

    if (_containsAny(raw, <String>[
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'connection refused',
      'connection reset',
      'no address associated with hostname',
    ])) {
      return fallback;
    }

    if (_containsAny(raw, <String>[
      'handshake',
      'certificate',
      'ssl',
      'tls',
    ])) {
      return 'Secure connection to the server failed';
    }

    if (_containsAny(raw, <String>[
      'timeout',
      'timed out',
    ])) {
      return 'The connection has timed out. Try again';
    }

    final String summarized = summarize(exception.toString());

    if (summarized.isEmpty) {
      return fallback;
    }

    return summarized;
  }

  static String resolveUserMessage({
    required String fallback,
    String? serverDetail,
    String? technicalLog,
  }) {
    final String? detail = _normalizeText(serverDetail);

    if (detail != null &&
        detail.isNotEmpty &&
        !_isInternalCode(detail) &&
        !_looksLikeTechnicalNoise(detail)) {
      return summarize(detail);
    }

    final String? fromLog = _extractMeaningfulFromLog(technicalLog);

    if (fromLog != null && fromLog.isNotEmpty) {
      return summarize(fromLog);
    }

    return fallback;
  }

  static String summarize(
    String? text, {
    int maxLength = _defaultMaxLength,
  }) {
    final String? normalized = _normalizeText(text);

    if (normalized == null || normalized.isEmpty) {
      return '';
    }

    String result = normalized;

    if (result.contains('\n')) {
      result = result.split('\n').first.trim();
    }

    if (result.length <= maxLength) {
      return result;
    }

    return '${result.substring(0, maxLength - 3)}...';
  }

  static String? _readCode(
    Map<String, dynamic>? extensions,
    String message,
  ) {
    final String? extensionCode =
        extensions?['exception_code']?.toString().trim();

    if (extensionCode != null && extensionCode.isNotEmpty) {
      return extensionCode;
    }

    if (_isInternalCode(message)) {
      return message;
    }

    return null;
  }

  static String? _readUserMessage({
    required Map<String, dynamic>? extensions,
    required String message,
  }) {
    final String? fromExtensions = _readDetail(extensions);

    if (fromExtensions != null && fromExtensions.isNotEmpty) {
      return fromExtensions;
    }

    if (_isInternalCode(message)) {
      return null;
    }

    return _normalizeText(message);
  }

  static String? _readDetail(Map<String, dynamic>? extensions) {
    if (extensions == null) {
      return null;
    }

    final Object? detail = extensions['detail'] ??
        extensions['user_message'] ??
        extensions['description'];

    return _normalizeText(detail?.toString());
  }

  static String _formatGraphQLError(GraphQLError error) {
    final String? detail = _readDetail(error.extensions);
    final StringBuffer buffer = StringBuffer(error.message);

    if (detail != null && detail.isNotEmpty && detail != error.message) {
      buffer.write(' — $detail');
    }

    final String? code = error.extensions?['exception_code']?.toString();

    if (code != null && code.isNotEmpty) {
      buffer.write(' [$code]');
    }

    return buffer.toString();
  }

  static String? _extractMeaningfulFromLog(String? technicalLog) {
    final String? normalized = _normalizeText(technicalLog);

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    if (_looksLikeTechnicalNoise(normalized)) {
      return null;
    }

    return normalized;
  }

  static bool _isInternalCode(String value) {
    return _internalCodes.contains(value.trim());
  }

  static bool matchesNoConnectionMessage(String? message) {
    final String? normalized = _normalizeText(message)?.toLowerCase();

    if (normalized == null) {
      return false;
    }

    return _containsAny(normalized, <String>[
      'no internet',
      'sem conexão',
      'sem conexao',
      'noconnection',
    ]);
  }

  static bool matchesCancelMessage(String? message) {
    final String? normalized = _normalizeText(message)?.toLowerCase();

    if (normalized == null) {
      return false;
    }

    return _containsAny(normalized, <String>[
      'cancel',
      'cancelad',
    ]);
  }

  static bool _looksLikeTechnicalNoise(String value) {
    final String lower = value.toLowerCase();

    return _containsAny(lower, <String>[
      'stack trace',
      'dart:',
      'package:',
      '#0 ',
      'graphql/flutter',
    ]);
  }

  static bool _containsAny(String value, List<String> needles) {
    for (final String needle in needles) {
      if (value.contains(needle)) {
        return true;
      }
    }

    return false;
  }

  static String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }

    final String trimmed = value.trim();

    if (trimmed.isEmpty || trimmed == 'null') {
      return null;
    }

    return trimmed;
  }
}
