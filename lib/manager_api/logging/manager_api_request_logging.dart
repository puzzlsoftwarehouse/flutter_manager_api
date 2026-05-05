part of 'package:manager_api/manager_api.dart';

final class _GraphqlBlockLineEntry {
  const _GraphqlBlockLineEntry({
    required this.body,
    required this.isError,
    required this.isAlert,
    required this.isCanceled,
    required this.latencyMs,
  });

  final String body;

  final bool isError;

  final bool isAlert;

  final bool isCanceled;

  final int? latencyMs;
}

mixin ManagerApiRequestLogging on ManagerToken {
  static const bool requestLoggerFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER', defaultValue: true);

  Map<String, int>? _graphqlBlockInflight;

  Map<String, Stopwatch>? _graphqlBlockWallClock;

  Map<String, List<_GraphqlBlockLineEntry>>? _graphqlBlockPendingLines;

  bool get _emitRequestLogs =>
      kDebugMode && ManagerApiRequestLogging.requestLoggerFromEnvironment;

  void _graphqlBlockBegin(String blockKey) {
    final Map<String, int> inflight =
        _graphqlBlockInflight ??= <String, int>{};

    final int nextCount = (inflight[blockKey] ?? 0) + 1;

    inflight[blockKey] = nextCount;

    if (nextCount == 1) {
      final Map<String, Stopwatch> wall =
          _graphqlBlockWallClock ??= <String, Stopwatch>{};

      wall[blockKey] = Stopwatch()..start();
    }
  }

  void _graphqlBlockAppend({
    required String blockKey,
    required String body,
    bool isError = false,
    bool isAlert = false,
    bool isCanceled = false,
    int? latencyMs,
  }) {
    final Map<String, List<_GraphqlBlockLineEntry>> pending =
        _graphqlBlockPendingLines ??=
            <String, List<_GraphqlBlockLineEntry>>{};

    final List<_GraphqlBlockLineEntry> bucket =
        pending.putIfAbsent(blockKey, () => <_GraphqlBlockLineEntry>[]);

    bucket.add(
      _GraphqlBlockLineEntry(
        body: body,
        isError: isError,
        isAlert: isAlert,
        isCanceled: isCanceled,
        latencyMs: latencyMs,
      ),
    );
  }

  void _graphqlBlockRelease(String blockKey) {
    final Map<String, int>? inflight = _graphqlBlockInflight;

    if (inflight == null) {
      return;
    }

    final int current = inflight[blockKey] ?? 0;
    final int next = current - 1;

    if (next <= 0) {
      inflight.remove(blockKey);

      if (inflight.isEmpty) {
        _graphqlBlockInflight = null;
      }

      final Map<String, Stopwatch>? wallMap = _graphqlBlockWallClock;
      final Stopwatch? wall = wallMap?.remove(blockKey);

      if (wallMap != null && wallMap.isEmpty) {
        _graphqlBlockWallClock = null;
      }

      wall?.stop();

      final int wallMs = wall?.elapsedMilliseconds ?? 0;

      final Map<String, List<_GraphqlBlockLineEntry>>? pendingMap =
          _graphqlBlockPendingLines;

      final List<_GraphqlBlockLineEntry> lines =
          pendingMap?.remove(blockKey) ?? <_GraphqlBlockLineEntry>[];

      if (pendingMap != null && pendingMap.isEmpty) {
        _graphqlBlockPendingLines = null;
      }

      _flushGraphqlBlock(
        blockKey: blockKey,
        lines: lines,
        wallMs: wallMs,
      );
    } else {
      inflight[blockKey] = next;
    }
  }

  void _flushGraphqlBlock({
    required String blockKey,
    required List<_GraphqlBlockLineEntry> lines,
    required int wallMs,
  }) {
    if (lines.isEmpty) {
      return;
    }

    if (!_emitRequestLogs) {
      return;
    }

    generateLog('------------------', neutralStyle: true);

    for (final _GraphqlBlockLineEntry line in lines) {
      generateLog(
        line.body,
        isError: line.isError,
        isAlert: line.isAlert,
        isCanceled: line.isCanceled,
        latencyMs: line.latencyMs,
      );
    }

    generateLog(
      '[$blockKey] total do bloco: ${_RequestLogFormatting.formatElapsed(wallMs)}',
      latencyMs: wallMs,
    );

    generateLog('------------------', neutralStyle: true);
  }

  String generateMsg({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    Stopwatch? stopwatch,
  }) {
    final String base = generateRequestLogBase(
      restRequest: restRequest,
      requestResult: requestResult,
    );
    final int elapsedMs = stopwatch?.elapsedMilliseconds ?? 0;

    return '$base - ${_RequestLogFormatting.formatElapsed(elapsedMs)}';
  }

  String generateRequestLogBase({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
  }) {
    final String type = requestResult?.type.toString().split(".").last ??
        restRequest?.type.toString().split(".").last ??
        "".toUpperCase();

    final String name = requestResult?.name ?? restRequest?.name ?? "";
    final Map<String, dynamic> variables =
        requestResult?.variables ?? restRequest?.body ?? <String, dynamic>{};
    final String path = requestResult?.path.toUpperCase() ?? "";

    return "[$path] [$type $name] - $variables";
  }

  void generateLog(
    String body, {
    bool isError = false,
    bool isAlert = false,
    bool isCanceled = false,
    int? latencyMs,
    bool neutralStyle = false,
  }) {
    if (!ManagerApiRequestLogging.requestLoggerFromEnvironment) {
      return;
    }

    if (!kDebugMode) {
      return;
    }

    if (!kIsWeb) {
      if (Platform.isIOS) {
        return debugPrint("GraphQL: $body");
      }
    }

    final Color accentColor = _RequestLogPalette.resolveAccent(
      isError: isError,
      isAlert: isAlert,
      isCanceled: isCanceled,
      neutralStyle: neutralStyle,
      latencyMs: latencyMs,
    );

    LogPrint(
      body,
      type: LogPrintType.custom,
      title: "Graphql",
      titleBackgroundColor: accentColor,
      messageColor: accentColor,
    );
  }
}
