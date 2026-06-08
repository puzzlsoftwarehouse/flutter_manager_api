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
import 'package:manager_api/utils/failure_message_resolver.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

export 'package:manager_api/models/graphql/graphql_policies.dart'
    show FetchPolicy, ErrorPolicy, CacheRereadPolicy;
export 'package:manager_api/models/graphql/graphql_retry_options.dart';
export 'package:manager_api/utils/graphql_cancel_token.dart';
export 'package:manager_api/utils/validate_fragments.dart';

part 'manager_api/logging/request_log_formatting.dart';

part 'manager_api/logging/request_log_palette.dart';

part 'manager_api/logging/manager_api_request_logging.dart';

DefaultFailures managerDefaultAPIFailures = DefaultFailures();

mixin class ManagerToken {
  String? token;
  Map<String, String>? headerCustom;
}

class ManagerAPI with ManagerToken, ManagerApiRequestLogging {
  static String? _token;
  static Map<String, String>? _headerCustom;
  Duration? timeOutDuration;
  final GraphQLRetryOptions graphQLRetryOptions;

  late GraphQLHelper _api;
  late RestHelper _restAPI;

  final List<Failure> _failures;
  Map<String, String>? Function(String? token)? headers;

  ManagerAPI({
    required DefaultFailures defaultFailures,
    List<Failure> failures = const <Failure>[],
    this.headers,
    this.timeOutDuration,
    this.graphQLRetryOptions = const GraphQLRetryOptions(),
  }) : _failures = [...DefaultAPIFailures.failures, ...failures] {
    managerDefaultAPIFailures = defaultFailures;
    _restAPI = RestHelper();

    final bool emitLogs =
        kDebugMode && ManagerApiRequestLogging.requestLoggerFromEnvironment;

    _api = GraphQLHelper(
      timeOutDuration: timeOutDuration,
      defaultRetryOptions: graphQLRetryOptions,
      log: emitLogs ? generateLog : null,
    );
  }

  Failure getDefaultFailure(
    String? text, {
    String? userMessage,
  }) {
    final String resolvedMessage = FailureMessageResolver.resolveUserMessage(
      fallback: managerDefaultAPIFailures.unknownError,
      serverDetail: userMessage,
      technicalLog: text,
    );

    return Failure(
      code: '000',
      message: resolvedMessage,
      log: text,
      error: text,
    );
  }

  String? getException(List<GraphQLError>? errors) {
    return FailureMessageResolver.extractGraphQLErrorDetails(errors).code ??
        (errors != null && errors.isNotEmpty
            ? errors.first.message.toString()
            : null);
  }

  Failure getGraphQLFailure(
    GraphQLOperationException? exception,
    List<Failure> failures,
  ) {
    final List<Failure> allFailures = [..._failures, ...failures];
    final GraphQLErrorDetails errorDetails =
        FailureMessageResolver.extractGraphQLErrorDetails(
      exception?.graphqlErrors,
    );

    if (exception?.linkException != null) {
      final String linkLog = exception!.linkException.toString();
      final String linkMessage =
          FailureMessageResolver.extractLinkExceptionMessage(
        exception.linkException?.originalException,
        fallback: managerDefaultAPIFailures.noConnectionError,
      );

      generateLog(linkLog, isError: true);

      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.noConnectionCode,
      )!
          .copyWith(
            message: linkMessage,
            error: linkLog,
          );
    }

    final String? exceptionCode =
        errorDetails.code ?? getException(exception?.graphqlErrors);

    if (exceptionCode == DefaultAPIFailures.noConnectionCode) {
      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.noConnectionCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    if (exceptionCode == DefaultAPIFailures.timeoutCode) {
      generateLog('GraphQL Request Timeout', isError: true);

      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.timeoutCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    if (exceptionCode == 'cancelled' ||
        exceptionCode == DefaultAPIFailures.cancelErrorCode) {
      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.cancelErrorCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    final Failure? failure = allFailures.firstWhereOrNull(
      (Failure item) => item.code == exceptionCode,
    );
    final Failure baseFailure = failure ??
        getDefaultFailure(
          errorDetails.technicalLog ?? exceptionCode,
          userMessage: errorDetails.userMessage,
        );
    final String resolvedMessage = FailureMessageResolver.resolveUserMessage(
      fallback: baseFailure.message,
      serverDetail: errorDetails.userMessage,
      technicalLog: errorDetails.technicalLog,
    );
    final Failure resultFailure = baseFailure.copyWith(
      message: resolvedMessage,
      error: errorDetails.technicalLog,
    );

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

    final String? logContext = _emitRequestLogs
        ? generateRequestLogBase(requestResult: request)
        : null;

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
        logContext: logContext,
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
      logContext: logContext,
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
      final RestRequest requestResult = convertRestRequest(request);
      if (requestResult.skipRequest != null) {
        if (_emitRequestLogs) {
          generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
        }

        return requestResult.skipRequest!.result;
      }

      final Stopwatch? stopwatch =
          _emitRequestLogs ? (Stopwatch()..start()) : null;

      final Map<String, dynamic>? result =
          await getCorrectRestRequest(requestResult);

      stopwatch?.stop();

      if (stopwatch != null) {
        generateLog(
          generateMsg(
            restRequest: requestResult,
            stopwatch: stopwatch,
          ),
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }

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
      if (_emitRequestLogs) {
        generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
      }

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
    if (ignoreCode != null) {
      requestResult = requestResult.copyWith(errorPolicy: ErrorPolicy.all);
    }

    final bool emitLogs = _emitRequestLogs;
    final String groupKey =
        _RequestLogFormatting.graphqlBlockKey(requestResult.name);
    final bool shouldLogRequest =
        emitLogs && _shouldLogGraphqlGroup(groupKey);
    final bool useBlock = shouldLogRequest &&
        ManagerApiRequestLogging.requestLoggerBlocFromEnvironment;
    final Stopwatch? stopwatch =
        shouldLogRequest ? (Stopwatch()..start()) : null;
    final String? blockKey =
        useBlock ? groupKey : null;

    if (blockKey != null) {
      _graphqlBlockBegin(blockKey);
    }

    try {
      final GraphQLQueryResult<Object?> result =
          await getCorrectGraphQLRequest(requestResult);
      onGraphQLRawResult?.call(result.data as Map<String, dynamic>?);
      stopwatch?.stop();

      final String? exceptionCode =
          getException(result.exception?.graphqlErrors);

      if (exceptionCode == "cancelled") {
        if (shouldLogRequest) {
          _emitGraphqlRequestLog(
            blockKey: blockKey,
            body:
                "${generateMsg(requestResult: requestResult, stopwatch: stopwatch)} - [CANCELLED]",
            isCanceled: true,
          );
        }

        return Left(DefaultAPIFailures.getFailureByCode(
            DefaultAPIFailures.cancelErrorCode)!);
      }

      if (shouldLogRequest) {
        _emitGraphqlRequestLog(
          blockKey: blockKey,
          body: generateMsg(
            requestResult: requestResult,
            stopwatch: stopwatch,
          ),
          latencyMs: stopwatch?.elapsedMilliseconds,
        );
      }

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
      if (stopwatch?.isRunning ?? false) {
        stopwatch!.stop();
      }

      if (shouldLogRequest) {
        _emitGraphqlRequestLog(
          blockKey: blockKey,
          body:
              "${generateRequestLogBase(requestResult: requestResult)} — exceção: $error",
          isError: true,
        );
      }

      rethrow;
    } finally {
      if (blockKey != null) {
        _graphqlBlockRelease(blockKey);
      }
    }
  }

  Failure getRestFailure(
    Map<String, dynamic> exception,
    List<Failure> failures,
  ) {
    final RestErrorDetails errorDetails =
        FailureMessageResolver.extractRestErrorDetails(exception);

    generateLog(
      'Rest Request Error: ${errorDetails.technicalLog ?? exception.toString()}',
      isError: true,
    );

    final List<Failure> allFailures = [..._failures, ...failures];

    if (errorDetails.isNoConnection) {
      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.noConnectionCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    if (errorDetails.isTimeout) {
      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.timeoutCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    if (errorDetails.isCancel) {
      return DefaultAPIFailures.getFailureByCode(
        DefaultAPIFailures.cancelErrorCode,
      )!
          .copyWith(
            error: errorDetails.technicalLog,
          );
    }

    final String? code = errorDetails.code;
    final Failure? failure = allFailures.firstWhereOrNull(
      (Failure item) => item.code == code,
    );

    if (failure != null) {
      return failure.copyWith(
        message: FailureMessageResolver.resolveUserMessage(
          fallback: failure.message,
          serverDetail: errorDetails.userMessage,
          technicalLog: errorDetails.technicalLog,
        ),
        error: errorDetails.technicalLog,
      );
    }

    return getDefaultFailure(
      '${code ?? ''} ${errorDetails.userMessage ?? ''}'.trim(),
      userMessage: errorDetails.userMessage,
    );
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
