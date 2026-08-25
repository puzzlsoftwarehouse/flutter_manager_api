part of 'package:manager_api/manager_api.dart';

typedef _RequestLogParts = ({String head, String vars, String label});

final class _GraphqlBlockLineEntry {
  const _GraphqlBlockLineEntry({
    required this.head,
    required this.vars,
    required this.label,
    required this.suffix,
    required this.isError,
    required this.isAlert,
    required this.isCanceled,
    required this.latencyMs,
  });

  final String head;

  final String vars;

  final String label;

  final String suffix;

  final bool isError;

  final bool isAlert;

  final bool isCanceled;

  final int? latencyMs;

  String get dedupeKey => '$head|$vars';
}

final class _GraphqlBlockGroup {
  _GraphqlBlockGroup(_GraphqlBlockLineEntry entry)
      : head = entry.head,
        vars = entry.vars,
        suffix = entry.suffix,
        latencyMs = entry.latencyMs,
        isError = entry.isError,
        isAlert = entry.isAlert,
        isCanceled = entry.isCanceled;

  final String head;

  final String vars;

  String suffix;

  int? latencyMs;

  bool isError;

  bool isAlert;

  bool isCanceled;

  int count = 1;

  void merge(_GraphqlBlockLineEntry entry) {
    count += 1;
    isError = isError || entry.isError;
    isAlert = isAlert || entry.isAlert;
    isCanceled = isCanceled || entry.isCanceled;

    final int? incoming = entry.latencyMs;

    if (incoming != null && (latencyMs == null || incoming > latencyMs!)) {
      latencyMs = incoming;
    }

    if (entry.suffix.isNotEmpty && !suffix.contains(entry.suffix)) {
      suffix = '$suffix${entry.suffix}';
    }
  }
}

mixin ManagerApiRequestLogging on ManagerToken {
  static const bool requestLoggerFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER', defaultValue: true);

  static const bool requestLoggerBlocFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER_BLOC', defaultValue: false);

  static const bool requestLoggerGroupFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER_GROUP', defaultValue: true);

  Map<String, int>? _graphqlBlockInflight;

  Map<String, Stopwatch>? _graphqlBlockWallClock;

  Map<String, List<_GraphqlBlockLineEntry>>? _graphqlBlockPendingLines;

  bool get _emitRequestLogs =>
      kDebugMode && ManagerApiRequestLogging.requestLoggerFromEnvironment;

  bool get _compactGraphqlNames =>
      ManagerApiRequestLogging.requestLoggerGroupFromEnvironment;

  bool get _boxGraphqlBlocks =>
      ManagerApiRequestLogging.requestLoggerBlocFromEnvironment;

  void logRequest({
    String? blockKey,
    String? waveKey,
    String? groupKey,
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    Stopwatch? stopwatch,
    String suffix = '',
    bool isError = false,
    bool isAlert = false,
    bool isCanceled = false,
    String title = 'GraphQL',
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
      groupKey: groupKey ?? blockKey,
    );
    final int? latencyMs = stopwatch?.elapsedMilliseconds;
    final String? bucketKey = blockKey ?? waveKey;

    if (bucketKey != null) {
      _graphqlBlockAppend(
        blockKey: bucketKey,
        entry: _GraphqlBlockLineEntry(
          head: parts.head,
          vars: parts.vars,
          label: parts.label,
          suffix: suffix,
          isError: isError,
          isAlert: isAlert,
          isCanceled: isCanceled,
          latencyMs: latencyMs,
        ),
      );

      return;
    }

    generateLog(
      _RequestLogFormatting.requestLine(
        head: parts.head,
        vars: parts.vars,
        latencyMs: latencyMs,
        suffix: suffix,
      ),
      isError: isError,
      isAlert: isAlert,
      isCanceled: isCanceled,
      latencyMs: latencyMs,
      title: title,
    );
  }

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
    required _GraphqlBlockLineEntry entry,
  }) {
    final Map<String, List<_GraphqlBlockLineEntry>> pending =
        _graphqlBlockPendingLines ??=
            <String, List<_GraphqlBlockLineEntry>>{};

    pending
        .putIfAbsent(blockKey, () => <_GraphqlBlockLineEntry>[])
        .add(entry);
  }

  void _graphqlBlockRelease(String blockKey, {required bool boxed}) {
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
        boxed: boxed,
      );
    } else {
      inflight[blockKey] = next;
    }
  }

  void _flushGraphqlBlock({
    required String blockKey,
    required List<_GraphqlBlockLineEntry> lines,
    required int wallMs,
    required bool boxed,
  }) {
    if (lines.isEmpty) {
      return;
    }

    if (!_emitRequestLogs) {
      return;
    }

    final Map<String, _GraphqlBlockGroup> groups =
        <String, _GraphqlBlockGroup>{};

    for (final _GraphqlBlockLineEntry entry in lines) {
      final _GraphqlBlockGroup? group = groups[entry.dedupeKey];

      if (group == null) {
        groups[entry.dedupeKey] = _GraphqlBlockGroup(entry);

        continue;
      }

      group.merge(entry);
    }

    if (boxed) {
      generateLog('┌ $blockKey', neutralStyle: true);
    }

    for (final _GraphqlBlockGroup group in groups.values) {
      generateLog(
        _RequestLogFormatting.requestLine(
          head: group.head,
          vars: group.vars,
          latencyMs: group.latencyMs,
          suffix: group.suffix,
          count: group.count,
        ),
        prefix: boxed ? '│ ' : '',
        isError: group.isError,
        isAlert: group.isAlert,
        isCanceled: group.isCanceled,
        latencyMs: group.latencyMs,
      );
    }

    if (!boxed) {
      return;
    }

    generateLog(
      '└ ${_blockSummary(
        lines: lines,
        groups: groups.values,
        wallMs: wallMs,
      )}',
      latencyMs: wallMs,
      showStatus: false,
    );
  }

  String _blockSummary({
    required List<_GraphqlBlockLineEntry> lines,
    required Iterable<_GraphqlBlockGroup> groups,
    required int wallMs,
  }) {
    int errors = 0;
    int canceled = 0;
    int slow = 0;
    int duplicated = 0;
    int slowestMs = -1;
    String slowestLabel = '';

    for (final _GraphqlBlockLineEntry line in lines) {
      if (line.isError) {
        errors += 1;
      }

      if (line.isCanceled) {
        canceled += 1;
      }

      final int? elapsed = line.latencyMs;

      if (elapsed == null) {
        continue;
      }

      if (_RequestLogFormatting.isSlow(elapsed)) {
        slow += 1;
      }

      if (elapsed > slowestMs) {
        slowestMs = elapsed;
        slowestLabel = line.label;
      }
    }

    for (final _GraphqlBlockGroup group in groups) {
      duplicated += group.count - 1;
    }

    final List<String> parts = <String>[
      _RequestLogFormatting.formatElapsed(wallMs),
      '${lines.length} ${lines.length == 1 ? 'req' : 'reqs'}',
    ];

    if (errors > 0) {
      parts.add('✕ $errors');
    }

    if (canceled > 0) {
      parts.add('⊘ $canceled');
    }

    if (slow > 0) {
      parts.add('! $slow slow');
    }

    if (duplicated > 0) {
      parts.add('×$duplicated dup');
    }

    if (lines.length > 1 && slowestMs >= 0) {
      parts.add(
        'slowest $slowestLabel '
        '${_RequestLogFormatting.formatElapsed(slowestMs)}',
      );
    }

    return parts.join(' · ');
  }

  String generateMsg({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    Stopwatch? stopwatch,
    String? groupKey,
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
      groupKey: groupKey,
    );

    return _RequestLogFormatting.requestLine(
      head: parts.head,
      vars: parts.vars,
      latencyMs: stopwatch?.elapsedMilliseconds,
    );
  }

  String generateRequestLogBase({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    String? groupKey,
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
      groupKey: groupKey,
    );

    return '${parts.head}  ${parts.vars}';
  }

  _RequestLogParts _requestLogParts({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    String? groupKey,
  }) {
    final String type = (requestResult?.type.toString().split(".").last ??
            restRequest?.type.toString().split(".").last ??
            "")
        .toUpperCase();

    final String label = _RequestLogFormatting.compactName(
      requestResult?.name ?? restRequest?.name ?? "",
      groupKey,
    );
    final Map<String, dynamic> variables =
        requestResult?.variables ?? restRequest?.body ?? <String, dynamic>{};
    final String target = restRequest != null ? ' ${restRequest.url}' : '';

    return (
      head: '${_RequestLogFormatting.typeColumn(type)} $label$target',
      vars: _RequestLogFormatting.formatVariables(variables),
      label: label,
    );
  }

  String _requestWaveKey({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    String? groupKey,
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
      groupKey: groupKey,
    );

    return '${parts.head}|${parts.vars}';
  }

  void generateLog(
    String body, {
    bool isError = false,
    bool isAlert = false,
    bool isCanceled = false,
    int? latencyMs,
    bool neutralStyle = false,
    bool showStatus = true,
    String prefix = '',
    String title = 'GraphQL',
  }) {
    if (!ManagerApiRequestLogging.requestLoggerFromEnvironment) {
      return;
    }

    if (!kDebugMode) {
      return;
    }

    final Color accentColor = _RequestLogPalette.resolveAccent(
      isError: isError,
      isAlert: isAlert,
      isCanceled: isCanceled,
      neutralStyle: neutralStyle,
      latencyMs: latencyMs,
    );

    final String status = showStatus && !neutralStyle
        ? '${_RequestLogFormatting.statusIcon(
            isError: isError,
            isAlert: isAlert,
            isCanceled: isCanceled,
            latencyMs: latencyMs,
          )} '
        : '';

    ManagerConsoleLog.emit(
      title: title,
      message: '$prefix$status$body',
      accent: accentColor,
    );
  }
}
