import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_print/log_print.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/graphql/graphql_read.dart';
import 'package:manager_api/graphql/graphql_helper.dart';
import 'package:manager_api/graphql/graphql_request.dart';
import 'package:manager_api/models/failure/default_failures.dart';
import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/models/graphql/graphql_policies.dart';
import 'package:manager_api/models/graphql/graphql_result.dart';
import 'package:manager_api/models/graphql/graphql_retry_options.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';
import 'package:manager_api/rest/rest_helper.dart';
import 'package:manager_api/rest/rest_request.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

export 'package:manager_api/models/graphql/graphql_policies.dart'
    show FetchPolicy, ErrorPolicy, CacheRereadPolicy;
export 'package:manager_api/models/graphql/graphql_retry_options.dart';
export 'package:manager_api/utils/graphql_cancel_token.dart';
export 'package:manager_api/utils/validate_fragments.dart';

DefaultFailures managerDefaultAPIFailures = DefaultFailures();

typedef _GraphqlBlockLineEntry = ({
  String body,
  bool isError,
  bool isAlert,
  bool isCanceled,
  int? latencyMs,
});

mixin class ManagerToken {
  String? token;
  Map<String, String>? headerCustom;
}

class ManagerAPI with ManagerToken {
  static String? _token;
  static Map<String, String>? _headerCustom;
  Duration? timeOutDuration;
  final GraphQLRetryOptions graphQLRetryOptions;

  late GraphQLHelper _api;
  late RestHelper _restAPI;

  final List<Failure> _failures;
  Map<String, String>? Function(String? token)? headers;

  final Map<String, int> _graphqlBlockInflight = <String, int>{};

  final Map<String, Stopwatch> _graphqlBlockWallClock = <String, Stopwatch>{};

  final Map<String, List<_GraphqlBlockLineEntry>> _graphqlBlockPendingLines =
      <String, List<_GraphqlBlockLineEntry>>{};

  ManagerAPI({
    required DefaultFailures defaultFailures,
    List<Failure> failures = const <Failure>[],
    this.headers,
    this.timeOutDuration,
    this.graphQLRetryOptions = const GraphQLRetryOptions(),
  }) : _failures = [...DefaultAPIFailures.failures, ...failures] {
    managerDefaultAPIFailures = defaultFailures;
    _restAPI = RestHelper();
    _api = GraphQLHelper(
      timeOutDuration: timeOutDuration,
      defaultRetryOptions: graphQLRetryOptions,
      log: generateLog,
    );
  }

  Failure getDefaultFailure(String? text) => Failure(
        code: "000",
        message: managerDefaultAPIFailures.unknownError,
        log: text,
      );

  String? getException(List<GraphQLError>? errors) {
    if (errors == null || errors.isEmpty) return null;
    if (errors.first.extensions != null) {
      return errors.first.extensions?['exception_code'].toString();
    }
    return errors.first.message.toString();
  }

  Failure getGraphQLFailure(
    GraphQLOperationException? exception,
    List<Failure> failures,
  ) {
    final List<Failure> allFailures = [..._failures, ...failures];

    if (exception?.linkException != null) {
      generateLog("${exception?.linkException.toString()}", isError: true);

      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.noConnectionCode)!;
    }

    String? exceptionCode = getException(exception?.graphqlErrors);

    if (exceptionCode == DefaultAPIFailures.noConnectionCode) {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.noConnectionCode)!;
    }

    if (exceptionCode == DefaultAPIFailures.timeoutCode) {
      generateLog("GraphQL Request Timeout", isError: true);

      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.timeoutCode)!;
    }

    if (exceptionCode == "cancelled") {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.cancelErrorCode)!;
    }

    final Failure? failure = allFailures
        .firstWhereOrNull((Failure failure) => failure.code == exceptionCode);

    final Failure resultFailure = (failure ?? getDefaultFailure(exceptionCode))
        .copyWith(
            error: exception?.graphqlErrors
                .map((GraphQLError item) => item.toString())
                .toList()
                .join('\n'));

    generateLog(resultFailure.error ?? resultFailure.message, isError: true);
    return resultFailure;
  }

  Future<GraphQLQueryResult<Object?>> getCorrectGraphQLRequest(
      GraphQLRequest request) async {
    String query = request.query ??
        (await GraphQLRead.get(
          path: request.path,
          type: request.type,
          requestName: request.name,
        ));

    if (request.type == RequestGraphQLType.mutation) {
      return await _api.mutation(
        data: query,
        token: request.token ?? token,
        headers: getCorrectHeaders(request: request),
        variables: request.variables,
        durationTimeOut: request.timeOutDuration ?? timeOutDuration,
        errorPolicy: request.errorPolicy,
        cancelToken: request.cancelToken,
        retryOptions: request.retryOptions,
        logContext: generateRequestLogBase(requestResult: request),
        cacheRereadPolicy:
            request.cacheRereadPolicy ?? CacheRereadPolicy.ignoreAll,
        fetchPolicy: request.fetchPolicy ?? FetchPolicy.networkOnly,
      );
    }

    return await _api.query(
      data: query,
      token: request.token ?? token,
      headers: getCorrectHeaders(request: request),
      variables: request.variables,
      durationTimeOut: request.timeOutDuration ?? timeOutDuration,
      errorPolicy: request.errorPolicy,
      cancelToken: request.cancelToken,
      retryOptions: request.retryOptions,
      logContext: generateRequestLogBase(requestResult: request),
      cacheRereadPolicy:
          request.cacheRereadPolicy ?? CacheRereadPolicy.ignoreAll,
      fetchPolicy: request.fetchPolicy ?? FetchPolicy.networkOnly,
    );
  }

  Map<String, String> getCorrectHeaders({
    GraphQLRequest<dynamic>? request,
    RestRequest? restRequest,
  }) {
    final Map<String, String> newResult =
        request?.headers ?? restRequest?.headers ?? <String, String>{};
    newResult.addAll(_headerCustom ?? <String, String>{});

    final Map<String, String> actualHeaders =
        headers?.call(request?.token ?? token) ?? <String, String>{};

    actualHeaders.addAll(newResult);
    return actualHeaders;
  }

  GraphQLRequest<dynamic> convertGraphQLRequest(
          Map<String, dynamic>? request) =>
      GraphQLRequest.fromJson(request ?? const <String, dynamic>{});

  Future<ResultLR<Failure, dynamic>> request({
    required String named,
    Map<String, dynamic>? request,
    int? ignoreCode,
    GraphQLCancelToken? cancelToken,
    void Function(Map<String, dynamic>? rawResult)? onGraphQLRawResult,
  }) async {
    if (request?['typeAPI'] == 'rest') {
      final Stopwatch stopwatch = Stopwatch()..start();
      final RestRequest requestResult = convertRestRequest(request);
      if (requestResult.skipRequest != null) {
        generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
        return requestResult.skipRequest!.result;
      }
      final Map<String, dynamic>? result =
          await getCorrectRestRequest(requestResult);
      stopwatch.stop();

      generateLog(
        generateMsg(
          restRequest: requestResult,
          stopwatch: stopwatch,
        ),
        latencyMs: stopwatch.elapsedMilliseconds,
      );

      if (result?['error'] != null) {
        return Left(getRestFailure(result!['error'], requestResult.failures));
      }
      return Right(requestResult.returnRequest(result!));
    }

    GraphQLRequest<dynamic> requestResult = convertGraphQLRequest(request);
    if (cancelToken != null) {
      requestResult = requestResult.copyWith(cancelToken: cancelToken);
    }
    if (requestResult.skipRequest != null) {
      generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
      return requestResult.skipRequest!.result;
    }

    return await identifyPermissionForRequest(
      requestResult: requestResult,
      ignoreCode: ignoreCode,
      onGraphQLRawResult: onGraphQLRawResult,
    );
  }

  Future<ResultLR<Failure, dynamic>> identifyPermissionForRequest({
    required GraphQLRequest<dynamic> requestResult,
    int? ignoreCode,
    void Function(Map<String, dynamic>? rawResult)? onGraphQLRawResult,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    if (ignoreCode != null) {
      requestResult = requestResult.copyWith(errorPolicy: ErrorPolicy.all);
    }

    final String blockKey = _graphqlOperationBlockKey(requestResult.name);

    _graphqlBlockBegin(blockKey);

    try {
      final GraphQLQueryResult<Object?> result =
          await getCorrectGraphQLRequest(requestResult);
      onGraphQLRawResult?.call(result.data as Map<String, dynamic>?);
      stopwatch.stop();

      final String? exceptionCode =
          getException(result.exception?.graphqlErrors);

      if (exceptionCode == "cancelled") {
        _graphqlBlockAppend(
          blockKey: blockKey,
          body:
              "${generateMsg(requestResult: requestResult, stopwatch: stopwatch)} - [CANCELLED]",
          isCanceled: true,
        );

        return Left(DefaultAPIFailures.getFailureByCode(
            DefaultAPIFailures.cancelErrorCode)!);
      }

      _graphqlBlockAppend(
        blockKey: blockKey,
        body: generateMsg(
          requestResult: requestResult,
          stopwatch: stopwatch,
        ),
        latencyMs: stopwatch.elapsedMilliseconds,
      );

      if (result.hasException && ignoreCode == null) {
        return Left(getGraphQLFailure(result.exception, requestResult.failures));
      }

      if (result.hasException && ignoreCode != null && result.data == null) {
        return Left(getGraphQLFailure(result.exception, requestResult.failures));
      }

      if (result.hasException && ignoreCode != null && result.data != null) {
        if (exceptionCode == ignoreCode.toString()) {
          final dynamic returned = await requestResult
              .returnRequest(result.data! as Map<String, dynamic>);
          return Right(returned);
        }
      }

      if (result.data != null && !result.hasException) {
        final dynamic returned = await requestResult
            .returnRequest(result.data! as Map<String, dynamic>);
        return Right(returned);
      }

      return Left(getGraphQLFailure(result.exception, requestResult.failures));
    } catch (error) {
      if (stopwatch.isRunning) {
        stopwatch.stop();
      }

      _graphqlBlockAppend(
        blockKey: blockKey,
        body:
            "${generateRequestLogBase(requestResult: requestResult)} — exceção: $error",
        isError: true,
      );

      rethrow;
    } finally {
      _graphqlBlockRelease(blockKey);
    }
  }

  String _graphqlOperationBlockKey(String operationName) {
    final int underscoreIndex = operationName.indexOf('_');

    if (underscoreIndex <= 0) {
      return operationName;
    }

    return operationName.substring(0, underscoreIndex);
  }

  void _graphqlBlockBegin(String blockKey) {
    final int nextCount = (_graphqlBlockInflight[blockKey] ?? 0) + 1;

    _graphqlBlockInflight[blockKey] = nextCount;

    if (nextCount == 1) {
      _graphqlBlockWallClock[blockKey] = Stopwatch()..start();
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
    final List<_GraphqlBlockLineEntry> bucket = _graphqlBlockPendingLines
        .putIfAbsent(blockKey, () => <_GraphqlBlockLineEntry>[]);

    bucket.add((
      body: body,
      isError: isError,
      isAlert: isAlert,
      isCanceled: isCanceled,
      latencyMs: latencyMs,
    ));
  }

  void _graphqlBlockRelease(String blockKey) {
    final int current = _graphqlBlockInflight[blockKey] ?? 0;
    final int next = current - 1;

    if (next <= 0) {
      _graphqlBlockInflight.remove(blockKey);

      final Stopwatch? wall = _graphqlBlockWallClock.remove(blockKey);

      wall?.stop();

      final int wallMs = wall?.elapsedMilliseconds ?? 0;

      final List<_GraphqlBlockLineEntry> lines =
          _graphqlBlockPendingLines.remove(blockKey) ?? <_GraphqlBlockLineEntry>[];

      _flushGraphqlBlock(
        blockKey: blockKey,
        lines: lines,
        wallMs: wallMs,
      );
    } else {
      _graphqlBlockInflight[blockKey] = next;
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

    if (!kDebugMode) {
      return;
    }

    final bool isLoggingEnabled = const bool.fromEnvironment(
      "REQUESTLOGGER",
      defaultValue: true,
    );

    if (!isLoggingEnabled) {
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
      '[$blockKey] total do bloco: ${_formatElapsedForLog(wallMs)}',
      latencyMs: wallMs,
    );

    generateLog('------------------', neutralStyle: true);
  }

  Failure getRestFailure(
    Map<String, dynamic> exception,
    List<Failure> failures,
  ) {
    generateLog("Rest Request Error: ${exception.toString()}", isError: true);

    final List<Failure> allFailures = [..._failures, ...failures];

    if (exception['type'] == 'noConnection') {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.noConnectionCode)!;
    }

    if (exception['type'] == 'timeout') {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.timeoutCode)!;
    }

    String? code;

    if (exception['code'] is int) {
      code = exception['code'].toString();
    } else {
      code = exception['code'];
    }

    Failure? failure =
        allFailures.firstWhereOrNull((Failure failure) => failure.code == code);

    return failure ??
        getDefaultFailure("${code ?? ""}  ${exception['message']}");
  }

  RestRequest convertRestRequest(Map<String, dynamic>? request) =>
      RestRequest.fromJson(request ?? const <String, dynamic>{});

  Future<Map<String, dynamic>?> getCorrectRestRequest(
      RestRequest request) async {
    if (request.bodyType == BodyType.bytes) {
      return await _restAPI.sendMedia(
        file: request.body!['file'],
        url: request.url,
        parameters: request.parameters ?? {},
        headers: getCorrectHeaders(restRequest: request),
        streamProgress: request.streamProgress,
        cancelToken: request.cancelToken,
      );
    }

    if (request.type == RequestRestType.get) {
      return await _restAPI.getRequest(
        url: request.url,
        headers: getCorrectHeaders(restRequest: request),
        responseType: request.bodyResponseType == RequestResponseBodyType.bytes
            ? ResponseType.bytes
            : ResponseType.json,
        timeout: request.timeOutDuration,
      );
    }

    if (request.type == RequestRestType.post) {
      return await _restAPI.postRequest(
        url: request.url,
        headers: getCorrectHeaders(restRequest: request),
        body: request.body,
        timeout: request.timeOutDuration,
      );
    }

    generateLog("REQUEST TYPE REST NOT FOUND", isError: true);
    return null;
  }

  String _formatElapsedForLog(int elapsedMs) {
    final String secondsPart = (elapsedMs / 1000).toStringAsFixed(1);

    return '${elapsedMs}ms (${secondsPart}s)';
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

    return "$base - ${_formatElapsedForLog(elapsedMs)}";
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

  Color _latencyColorForLog(int elapsedMs) {
    const Color greenFast = Color(0xFF69F0AE);
    const Color strongRed = Color(0xFF8B0000);

    if (elapsedMs >= 2000) {
      return strongRed;
    }

    final double t = (elapsedMs / 2000).clamp(0.0, 1.0);

    if (t <= 0.5) {
      return Color.lerp(greenFast, Colors.amber.shade400, t * 2)!;
    }

    return Color.lerp(Colors.amber.shade700, Colors.red.shade700, (t - 0.5) * 2)!;
  }

  Color _getLogTitleColor({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
  }) {
    if (isAlert) return Colors.yellowAccent;
    if (isError) return Colors.redAccent;
    if (isCanceled) return Colors.white70;
    return Colors.amber;
  }

  Color _resolveLogAccentColor({
    required bool isError,
    required bool isAlert,
    required bool isCanceled,
    required bool neutralStyle,
    required int? latencyMs,
  }) {
    if (neutralStyle) {
      return Colors.blueGrey.shade600;
    }

    if (isError || isAlert || isCanceled) {
      return _getLogTitleColor(
        isError: isError,
        isAlert: isAlert,
        isCanceled: isCanceled,
      );
    }

    if (latencyMs != null) {
      return _latencyColorForLog(latencyMs);
    }

    return Colors.amber;
  }

  void generateLog(
    String body, {
    bool isError = false,
    bool isAlert = false,
    bool isCanceled = false,
    int? latencyMs,
    bool neutralStyle = false,
  }) {
    if (!kDebugMode) return;

    final bool isLoggingEnabled = const bool.fromEnvironment(
      "REQUESTLOGGER",
      defaultValue: true,
    );
    if (!isLoggingEnabled) return;

    if (!kIsWeb) {
      if (Platform.isIOS) {
        return debugPrint("GraphQL: $body");
      }
    }

    final Color accentColor = _resolveLogAccentColor(
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

  @override
  set token(String? value) {
    _token = value;
    super.token = value;
  }

  @override
  String? get token => _token;

  @override
  set headerCustom(Map<String, String>? header) {
    _headerCustom = {...?header};
    super.headerCustom = {...?header};
  }

  @override
  Map<String, String>? get headerCustom => _headerCustom;
}
