class GraphQLRetryOptions {
  final bool enabled;
  final int maxAttempts;
  final Duration initialDelay;

  const GraphQLRetryOptions({
    this.enabled = true,
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
  }) : assert(maxAttempts > 0, 'maxAttempts must be greater than zero');

  GraphQLRetryOptions copyWith({
    bool? enabled,
    int? maxAttempts,
    Duration? initialDelay,
  }) {
    return GraphQLRetryOptions(
      enabled: enabled ?? this.enabled,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initialDelay: initialDelay ?? this.initialDelay,
    );
  }

  factory GraphQLRetryOptions.fromJson(Map<String, dynamic> json) {
    final delayMilliseconds = json['initialDelayMilliseconds'];
    final delaySeconds = json['initialDelaySeconds'];

    return GraphQLRetryOptions(
      enabled: json['enabled'] ?? true,
      maxAttempts: json['maxAttempts'] ?? 3,
      initialDelay: Duration(
        milliseconds: delayMilliseconds ??
            ((delaySeconds != null ? delaySeconds * 1000 : null) ?? 1000),
      ),
    );
  }

  Map<String, dynamic> get toJson => {
        'enabled': enabled,
        'maxAttempts': maxAttempts,
        'initialDelayMilliseconds': initialDelay.inMilliseconds,
      };
}
