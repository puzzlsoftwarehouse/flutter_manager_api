part of 'package:manager_api/manager_api.dart';

typedef _RequestLogParts = ({
  String head,
  String vars,
  String name,
  String type,
  String target,
});

typedef _GraphqlNodeStats = ({
  int requests,
  int? latencyMs,
  bool isError,
  bool isAlert,
  bool isCanceled,
});

typedef _GraphqlCollapsedNode = ({String label, _GraphqlTreeNode node});

typedef _GraphqlTreeSlot = ({
  String label,
  _GraphqlBlockGroup? group,
  _GraphqlTreeNode? node,
});

final class _GraphqlBlockLineEntry {
  const _GraphqlBlockLineEntry({
    required this.head,
    required this.vars,
    required this.name,
    required this.type,
    required this.target,
    required this.suffix,
    required this.isError,
    required this.isAlert,
    required this.isCanceled,
    required this.latencyMs,
  });

  final String head;

  final String vars;

  final String name;

  final String type;

  final String target;

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
        name = entry.name,
        type = entry.type,
        target = entry.target,
        suffix = entry.suffix,
        latencyMs = entry.latencyMs,
        isError = entry.isError,
        isAlert = entry.isAlert,
        isCanceled = entry.isCanceled;

  final String head;

  final String vars;

  final String name;

  final String type;

  final String target;

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

final class _GraphqlTreeNode {
  _GraphqlTreeNode(this.label);

  final String label;

  final Map<String, _GraphqlTreeNode> children =
      <String, _GraphqlTreeNode>{};

  final List<_GraphqlBlockGroup> groups = <_GraphqlBlockGroup>[];
}

mixin ManagerApiRequestLogging on ManagerToken {
  static const bool requestLoggerFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER', defaultValue: true);

  static const bool requestLoggerBlocFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER_BLOC', defaultValue: false);

  static const bool requestLoggerGroupFromEnvironment =
      bool.fromEnvironment('REQUESTLOGGER_GROUP', defaultValue: true);

  static const int requestLoggerBlockIdleMsFromEnvironment =
      int.fromEnvironment('REQUESTLOGGER_BLOCK_IDLE_MS', defaultValue: 150);

  static const int requestLoggerBlockMaxLinesFromEnvironment =
      int.fromEnvironment('REQUESTLOGGER_BLOCK_MAX', defaultValue: 120);

  Map<String, int>? _graphqlBlockInflight;

  Map<String, Stopwatch>? _graphqlBlockWallClock;

  Map<String, List<_GraphqlBlockLineEntry>>? _graphqlBlockPendingLines;

  Map<String, Timer>? _graphqlBlockFlushTimers;

  bool get _emitRequestLogs =>
      kDebugMode && ManagerApiRequestLogging.requestLoggerFromEnvironment;

  bool get _cascadeGraphqlNames =>
      ManagerApiRequestLogging.requestLoggerGroupFromEnvironment;

  bool get _boxGraphqlBlocks =>
      ManagerApiRequestLogging.requestLoggerBlocFromEnvironment;

  void logRequest({
    String? blockKey,
    String? waveKey,
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
    );
    final int? latencyMs = stopwatch?.elapsedMilliseconds;
    final String? bucketKey = blockKey ?? waveKey;

    if (bucketKey != null) {
      _graphqlBlockAppend(
        blockKey: bucketKey,
        entry: _GraphqlBlockLineEntry(
          head: parts.head,
          vars: parts.vars,
          name: parts.name,
          type: parts.type,
          target: parts.target,
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
    _cancelGraphqlBlockFlush(blockKey);

    final Map<String, int> inflight =
        _graphqlBlockInflight ??= <String, int>{};

    final int nextCount = (inflight[blockKey] ?? 0) + 1;

    inflight[blockKey] = nextCount;

    if (nextCount == 1) {
      final Map<String, Stopwatch> wall =
          _graphqlBlockWallClock ??= <String, Stopwatch>{};

      (wall[blockKey] ??= Stopwatch()).start();
    }
  }

  void _cancelGraphqlBlockFlush(String blockKey) {
    final Map<String, Timer>? timers = _graphqlBlockFlushTimers;

    if (timers == null) {
      return;
    }

    timers.remove(blockKey)?.cancel();

    if (timers.isEmpty) {
      _graphqlBlockFlushTimers = null;
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

    final int next = (inflight[blockKey] ?? 0) - 1;

    if (next > 0) {
      inflight[blockKey] = next;

      return;
    }

    inflight.remove(blockKey);

    if (inflight.isEmpty) {
      _graphqlBlockInflight = null;
    }

    _graphqlBlockWallClock?[blockKey]?.stop();

    final int idleMs =
        ManagerApiRequestLogging.requestLoggerBlockIdleMsFromEnvironment;
    final int pendingCount =
        _graphqlBlockPendingLines?[blockKey]?.length ?? 0;
    final bool reachedCap = pendingCount >=
        ManagerApiRequestLogging.requestLoggerBlockMaxLinesFromEnvironment;

    if (idleMs <= 0 || reachedCap) {
      _graphqlBlockFlushNow(blockKey, boxed: boxed);

      return;
    }

    final Map<String, Timer> timers =
        _graphqlBlockFlushTimers ??= <String, Timer>{};

    timers[blockKey] = Timer(
      Duration(milliseconds: idleMs),
      () => _graphqlBlockFlushNow(blockKey, boxed: boxed),
    );
  }

  void _graphqlBlockFlushNow(String blockKey, {required bool boxed}) {
    _cancelGraphqlBlockFlush(blockKey);

    final Map<String, Stopwatch>? wallMap = _graphqlBlockWallClock;
    final Stopwatch? wall = wallMap?.remove(blockKey);

    if (wallMap != null && wallMap.isEmpty) {
      _graphqlBlockWallClock = null;
    }

    wall?.stop();

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
      wallMs: wall?.elapsedMilliseconds ?? 0,
      boxed: boxed,
    );
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

    if (!boxed || lines.length == 1) {
      for (final _GraphqlBlockGroup group in groups.values) {
        _emitGraphqlFlatLine(group: group, prefix: '');
      }

      return;
    }

    final bool cascade = _cascadeGraphqlNames && groups.length > 1;
    String header = blockKey;

    if (cascade) {
      final _GraphqlCollapsedNode root = _hoistGraphqlRoot(
        _buildGraphqlTree(blockKey: blockKey, groups: groups.values),
      );

      header = root.label;

      generateLog('┌ $header', neutralStyle: true);

      _emitGraphqlTreeChildren(
        node: root.node,
        indent: '',
        extras: root.node.groups,
        extrasLabel: header,
      );
    } else {
      generateLog('┌ $header', neutralStyle: true);

      for (final _GraphqlBlockGroup group in groups.values) {
        _emitGraphqlFlatLine(group: group, prefix: '│ ');
      }
    }

    generateLog(
      '└ ${_blockSummary(
        lines: lines,
        groups: groups.values,
        wallMs: wallMs,
        namePrefix: cascade ? header : '',
      )}',
      latencyMs: wallMs,
      showStatus: false,
    );
  }

  _GraphqlCollapsedNode _hoistGraphqlRoot(_GraphqlTreeNode root) {
    String label = root.label;
    _GraphqlTreeNode current = root;

    while (current.groups.isEmpty && current.children.length == 1) {
      final _GraphqlCollapsedNode collapsed =
          _collapseGraphqlNode(current.children.values.first);

      if (collapsed.node.groups.isNotEmpty ||
          collapsed.node.children.isEmpty) {
        break;
      }

      label = '${label}_${collapsed.label}';
      current = collapsed.node;
    }

    return (label: label, node: current);
  }

  void _emitGraphqlFlatLine({
    required _GraphqlBlockGroup group,
    required String prefix,
  }) {
    generateLog(
      _RequestLogFormatting.requestLine(
        head: group.head,
        vars: group.vars,
        latencyMs: group.latencyMs,
        suffix: group.suffix,
        count: group.count,
      ),
      prefix: prefix,
      isError: group.isError,
      isAlert: group.isAlert,
      isCanceled: group.isCanceled,
      latencyMs: group.latencyMs,
    );
  }

  _GraphqlTreeNode _buildGraphqlTree({
    required String blockKey,
    required Iterable<_GraphqlBlockGroup> groups,
  }) {
    final _GraphqlTreeNode root = _GraphqlTreeNode(blockKey);

    for (final _GraphqlBlockGroup group in groups) {
      final List<String> segments = group.name.split('_');
      final int start =
          segments.isNotEmpty && segments.first == blockKey ? 1 : 0;

      _GraphqlTreeNode node = root;

      for (int index = start; index < segments.length; index++) {
        final String segment = segments[index];

        if (segment.isEmpty) {
          continue;
        }

        node = node.children.putIfAbsent(
          segment,
          () => _GraphqlTreeNode(segment),
        );
      }

      node.groups.add(group);
    }

    return root;
  }

  _GraphqlCollapsedNode _collapseGraphqlNode(_GraphqlTreeNode node) {
    String label = node.label;
    _GraphqlTreeNode current = node;

    while (current.groups.isEmpty && current.children.length == 1) {
      final _GraphqlTreeNode child = current.children.values.first;

      label = '${label}_${child.label}';
      current = child;
    }

    return (label: label, node: current);
  }

  void _emitGraphqlTreeChildren({
    required _GraphqlTreeNode node,
    required String indent,
    required List<_GraphqlBlockGroup> extras,
    required String extrasLabel,
  }) {
    final List<_GraphqlTreeSlot> slots = <_GraphqlTreeSlot>[
      for (final _GraphqlBlockGroup group in extras)
        (label: extrasLabel, group: group, node: null),
    ];

    for (final _GraphqlTreeNode child in node.children.values) {
      final _GraphqlCollapsedNode collapsed = _collapseGraphqlNode(child);

      if (collapsed.node.children.isNotEmpty) {
        slots.add((label: collapsed.label, group: null, node: collapsed.node));

        continue;
      }

      for (final _GraphqlBlockGroup group in collapsed.node.groups) {
        slots.add((label: collapsed.label, group: group, node: null));
      }
    }

    int bodyWidth = 0;

    for (final _GraphqlTreeSlot slot in slots) {
      final int width = _graphqlSlotBody(slot).length;

      if (width > bodyWidth) {
        bodyWidth = width;
      }
    }

    for (int index = 0; index < slots.length; index++) {
      final _GraphqlTreeSlot slot = slots[index];
      final bool isLast = index == slots.length - 1;
      final _GraphqlBlockGroup? group = slot.group;

      if (group != null) {
        _emitGraphqlLeaf(
          group: group,
          indent: indent,
          body: _graphqlSlotBody(slot),
          bodyWidth: bodyWidth,
          isLast: isLast,
        );

        continue;
      }

      _emitGraphqlTreeNode(
        label: slot.label,
        node: slot.node!,
        indent: indent,
        bodyWidth: bodyWidth,
        isLast: isLast,
      );
    }
  }

  String _graphqlSlotBody(_GraphqlTreeSlot slot) {
    final _GraphqlBlockGroup? group = slot.group;

    if (group == null) {
      return slot.label;
    }

    return _RequestLogFormatting.treeLabelBody(
      label: slot.label,
      target: group.target,
      count: group.count,
    );
  }

  void _emitGraphqlTreeNode({
    required String label,
    required _GraphqlTreeNode node,
    required String indent,
    required int bodyWidth,
    required bool isLast,
  }) {
    final bool single = node.groups.length == 1;

    if (single) {
      final _GraphqlBlockGroup group = node.groups.first;

      _emitGraphqlLeaf(
        group: group,
        indent: indent,
        body: _RequestLogFormatting.treeLabelBody(
          label: label,
          target: group.target,
          count: group.count,
        ),
        bodyWidth: bodyWidth,
        isLast: isLast,
      );
    } else {
      _emitGraphqlBranch(
        node: node,
        indent: indent,
        label: label,
        bodyWidth: bodyWidth,
        isLast: isLast,
      );
    }

    final String trail = isLast
        ? _RequestLogFormatting.branchTrailBlank
        : _RequestLogFormatting.branchTrailPipe;

    _emitGraphqlTreeChildren(
      node: node,
      indent: '$indent$trail',
      extras: single ? const <_GraphqlBlockGroup>[] : node.groups,
      extrasLabel: label,
    );
  }

  void _emitGraphqlLeaf({
    required _GraphqlBlockGroup group,
    required String indent,
    required String body,
    required int bodyWidth,
    required bool isLast,
  }) {
    generateLog(
      _RequestLogFormatting.treeRequestLine(
        latencyMs: group.latencyMs,
        type: group.type,
        indent: '$indent${_graphqlBranch(isLast)}',
        body: body,
        bodyWidth: bodyWidth,
        vars: group.vars,
        suffix: group.suffix,
      ),
      prefix: '│ ',
      isError: group.isError,
      isAlert: group.isAlert,
      isCanceled: group.isCanceled,
      latencyMs: group.latencyMs,
    );
  }

  void _emitGraphqlBranch({
    required _GraphqlTreeNode node,
    required String indent,
    required String label,
    required int bodyWidth,
    required bool isLast,
  }) {
    final _GraphqlNodeStats stats = _graphqlNodeStats(node);
    final int? latencyMs = stats.latencyMs;
    final List<String> detail = <String>[
      '${stats.requests} ${stats.requests == 1 ? 'req' : 'reqs'}',
      if (latencyMs != null) _RequestLogFormatting.formatElapsed(latencyMs),
    ];

    generateLog(
      _RequestLogFormatting.treeBranchLine(
        indent: '$indent${_graphqlBranch(isLast)}',
        body: label,
        bodyWidth: bodyWidth,
        detail: detail.join(' · '),
      ),
      prefix: '│ ',
      isError: stats.isError,
      isAlert: stats.isAlert,
      isCanceled: stats.isCanceled,
      neutralStyle: !stats.isError && !stats.isAlert && !stats.isCanceled,
      showStatus: false,
    );
  }

  String _graphqlBranch(bool isLast) => isLast
      ? _RequestLogFormatting.branchLast
      : _RequestLogFormatting.branchMiddle;

  _GraphqlNodeStats _graphqlNodeStats(_GraphqlTreeNode node) {
    int requests = 0;
    int slowestMs = -1;
    bool isError = false;
    bool isAlert = false;
    bool isCanceled = false;

    final List<_GraphqlTreeNode> pending = <_GraphqlTreeNode>[node];

    while (pending.isNotEmpty) {
      final _GraphqlTreeNode current = pending.removeLast();

      for (final _GraphqlBlockGroup group in current.groups) {
        requests += group.count;
        isError = isError || group.isError;
        isAlert = isAlert || group.isAlert;
        isCanceled = isCanceled || group.isCanceled;

        final int? elapsed = group.latencyMs;

        if (elapsed != null && elapsed > slowestMs) {
          slowestMs = elapsed;
        }
      }

      pending.addAll(current.children.values);
    }

    return (
      requests: requests,
      latencyMs: slowestMs < 0 ? null : slowestMs,
      isError: isError,
      isAlert: isAlert,
      isCanceled: isCanceled,
    );
  }

  String _blockSummary({
    required List<_GraphqlBlockLineEntry> lines,
    required Iterable<_GraphqlBlockGroup> groups,
    required int wallMs,
    String namePrefix = '',
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
        slowestLabel = line.name;
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
        'slowest ${_RequestLogFormatting.relativeName(
          slowestLabel,
          namePrefix,
        )} ${_RequestLogFormatting.formatElapsed(slowestMs)}',
      );
    }

    return parts.join(' · ');
  }

  String generateMsg({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    Stopwatch? stopwatch,
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
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
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
    );

    return '${parts.head}  ${parts.vars}';
  }

  _RequestLogParts _requestLogParts({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
  }) {
    final String type = (requestResult?.type.toString().split(".").last ??
            restRequest?.type.toString().split(".").last ??
            "")
        .toUpperCase();

    final String name = requestResult?.name ?? restRequest?.name ?? "";
    final Map<String, dynamic> variables =
        requestResult?.variables ?? restRequest?.body ?? <String, dynamic>{};
    final String target = restRequest != null ? ' ${restRequest.url}' : '';

    return (
      head: '${_RequestLogFormatting.typeColumn(type)} $name$target',
      vars: _RequestLogFormatting.formatVariables(variables),
      name: name,
      type: type,
      target: target,
    );
  }

  String _requestWaveKey({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
  }) {
    final _RequestLogParts parts = _requestLogParts(
      restRequest: restRequest,
      requestResult: requestResult,
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
      badge: isError ? ManagerConsoleLog.errorBadge : null,
    );
  }
}
