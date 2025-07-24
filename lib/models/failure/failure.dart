class Failure {
  final String code;
  final String title;
  final String message;
  final String? _log;
  final String? error;

  Failure({
    required this.code,
    String? title,
    String? message,
    String? log,
    this.error,
  })  : _log = log ?? '[$code] $message',
        title = title ?? 'Error!',
        message = message ?? "Unknown error, contact our support";

  String get log => _log ?? message;

  Failure copyWith({
    String? code,
    String? title,
    String? message,
    String? log,
    String? error,
  }) =>
      Failure(
        code: code ?? this.code,
        title: title ?? this.title,
        message: message ?? this.message,
        log: log ?? this.log,
        error: error ?? this.error,
      );
}
