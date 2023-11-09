class Failure {
  final String code;
  final String title;
  final String message;
  final String? _log;
  Failure({
    required this.code,
    String? title,
    String? message,
    String? log,
  })  : _log = log,
        title = title ?? '$code: Warning!',
        message = message ?? "Unknown error, contact our support";

  String get log => _log ?? message;

  Failure copyWith({
    String? code,
    String? title,
    String? message,
    String? log,
  }) =>
      Failure(
        code: code ?? this.code,
        title: title ?? this.title,
        message: message ?? this.message,
        log: log ?? this.log,
      );
}
