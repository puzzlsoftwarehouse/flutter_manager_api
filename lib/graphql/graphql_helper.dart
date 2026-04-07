import 'dart:async';

import 'package:dio/dio.dart';
import 'package:manager_api/models/graphql/graphql_policies.dart';
import 'package:manager_api/models/graphql/graphql_result.dart';
import 'package:manager_api/models/graphql/graphql_retry_options.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

typedef GraphQLLog = void Function(
  String body, {
  bool isError,
  bool isAlert,
  bool isCanceled,
});

class GraphQLHelper implements IGraphQLHelper {
  Duration? timeOutDuration;
  final GraphQLRetryOptions defaultRetryOptions;
  final GraphQLLog? log;

  final Dio _dio = Dio();
  Dio get _client => _dio;

  GraphQLHelper({
    this.timeOutDuration,
    this.defaultRetryOptions = const GraphQLRetryOptions(),
    this.log,
  });

  Duration get _defaultTimeout => const Duration(seconds: 15);

  String _url(Map<String, String>? headers) {
    if (headers != null && headers['apiUrl'] != null) {
      final url = headers['apiUrl']!;
      return url.endsWith('/graphql') ? url : '$url/graphql';
    }
    return '${const String.fromEnvironment("BASEAPIURL")}/graphql';
  }

  Map<String, String> _requestHeaders(
      String? token, Map<String, String>? headers) {
    if (headers != null) {
      final map = Map<String, String>.from(headers);
      map.remove('apiUrl');
      return map;
    }
    if (token != null) {
      return {
        'Authorization':
            '${const String.fromEnvironment("BASETOKENPROJECT")}$token',
      };
    }
    return {};
  }

  GraphQLQueryResult<Object?> _parseResponse(
    Response<dynamic> response,
    ErrorPolicy? errorPolicy,
  ) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      return GraphQLQueryResult(
        exception: GraphQLOperationException(
          graphqlErrors: [
            GraphQLError(
                message: 'Invalid response',
                extensions: {'exception_code': '000'}),
          ],
        ),
      );
    }

    final rawData = body['data'];
    final rawErrors = body['errors'];
    final List<dynamic>? errorsList =
        rawErrors is List ? List<dynamic>.from(rawErrors) : null;

    List<GraphQLError>? graphqlErrors;
    if (errorsList != null && errorsList.isNotEmpty) {
      graphqlErrors = errorsList.map((dynamic e) {
        final map =
            e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
        final message = map['message']?.toString() ?? 'Unknown error';
        final ext = map['extensions'];
        final extensions = ext is Map ? Map<String, dynamic>.from(ext) : null;
        return GraphQLError(message: message, extensions: extensions);
      }).toList();
    }

    final exception = graphqlErrors != null
        ? GraphQLOperationException(graphqlErrors: graphqlErrors)
        : null;

    final data = rawData is Map<String, dynamic>
        ? rawData
        : (rawData != null ? {'data': rawData} : null);

    return GraphQLQueryResult<Object?>(
      data: data,
      exception: exception,
    );
  }

  GraphQLQueryResult<Object?> _timeOutResult() => GraphQLQueryResult(
        exception: GraphQLOperationException(
          graphqlErrors: [const GraphQLError(message: 'timeout')],
        ),
      );

  GraphQLQueryResult<Object?> _noConnectionResult() => GraphQLQueryResult(
        exception: GraphQLOperationException(
          graphqlErrors: [const GraphQLError(message: 'noConnection')],
        ),
      );

  GraphQLQueryResult<Object?> _cancelledResult() => GraphQLQueryResult(
        exception: GraphQLOperationException(
          graphqlErrors: [const GraphQLError(message: 'cancelled')],
        ),
      );

  @override
  Future<GraphQLQueryResult<Object?>> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    GraphQLRetryOptions? retryOptions,
    String? logContext,
    CacheRereadPolicy cacheRereadPolicy = CacheRereadPolicy.ignoreAll,
    FetchPolicy fetchPolicy = FetchPolicy.networkOnly,
  }) async =>
      _execute(
        data: data,
        token: token,
        headers: headers,
        variables: variables,
        durationTimeOut: durationTimeOut,
        errorPolicy: errorPolicy,
        cancelToken: cancelToken,
        retryOptions: retryOptions,
        logContext: logContext,
      );

  @override
  Future<GraphQLQueryResult<Object?>> query({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    GraphQLRetryOptions? retryOptions,
    String? logContext,
    CacheRereadPolicy cacheRereadPolicy = CacheRereadPolicy.ignoreAll,
    FetchPolicy fetchPolicy = FetchPolicy.networkOnly,
  }) async =>
      _execute(
        data: data,
        token: token,
        headers: headers,
        variables: variables,
        durationTimeOut: durationTimeOut,
        errorPolicy: errorPolicy,
        cancelToken: cancelToken,
        retryOptions: retryOptions,
        logContext: logContext,
      );

  Future<GraphQLQueryResult<Object?>> _execute({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    GraphQLRetryOptions? retryOptions,
    String? logContext,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledResult();
    }

    final GraphQLRetryOptions resolvedRetryOptions =
        retryOptions ?? defaultRetryOptions;
    final int attempts =
        resolvedRetryOptions.enabled ? resolvedRetryOptions.maxAttempts : 1;

    for (int attempt = 1; attempt <= attempts; attempt++) {
      final outcome = await _performAttempt(
        data: data,
        token: token,
        headers: headers,
        variables: variables,
        durationTimeOut: durationTimeOut,
        errorPolicy: errorPolicy,
        cancelToken: cancelToken,
      );

      if (!outcome.shouldRetry || attempt == attempts) {
        return outcome.result;
      }

      final delay = _retryDelay(
        initialDelay: resolvedRetryOptions.initialDelay,
        attempt: attempt,
      );

      _logRetry(
        logContext: logContext,
        attempt: attempt,
        totalAttempts: attempts,
        delay: delay,
      );

      final shouldContinue = await _waitBeforeRetry(
        delay: delay,
        cancelToken: cancelToken,
      );

      if (!shouldContinue) {
        return _cancelledResult();
      }
    }

    return _noConnectionResult();
  }

  Future<_ExecutionOutcome> _performAttempt({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
  }) async {
    CancelToken? dioCancelToken;
    if (cancelToken != null) {
      dioCancelToken = CancelToken();
      final tokenToCancel = dioCancelToken;
      cancelToken.whenCancelled.then((_) {
        if (!tokenToCancel.isCancelled) {
          tokenToCancel.cancel('cancelled');
        }
      });
    }

    final url = _url(headers);
    final timeout = durationTimeOut ?? timeOutDuration ?? _defaultTimeout;

    try {
      final resultFuture = _client.post<Map<String, dynamic>>(
        url,
        data: {'query': data, 'variables': variables},
        options: Options(
          headers: _requestHeaders(token, headers),
          sendTimeout: timeout,
          receiveTimeout: timeout,
          contentType: 'application/json',
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
        cancelToken: dioCancelToken,
      );

      GraphQLQueryResult<Object?> result;

      if (cancelToken != null) {
        result = await Future.any<GraphQLQueryResult<Object?>>([
          resultFuture.then((r) => _handleResponse(r, errorPolicy)),
          cancelToken.whenCancelled
              .then<GraphQLQueryResult<Object?>>((_) => _cancelledResult()),
        ]);
        if (cancelToken.isCancelled) {
          return _ExecutionOutcome(
            result: _cancelledResult(),
            shouldRetry: false,
          );
        }
      } else {
        result = await resultFuture
            .timeout(timeout, onTimeout: () => throw _TimeoutException())
            .then((r) => _handleResponse(r, errorPolicy));
      }

      return _ExecutionOutcome(result: result, shouldRetry: false);
    } on _TimeoutException {
      return _ExecutionOutcome(result: _timeOutResult(), shouldRetry: true);
    } on DioException catch (e) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _ExecutionOutcome(
          result: _cancelledResult(),
          shouldRetry: false,
        );
      }
      if (e.type == DioExceptionType.cancel) {
        return _ExecutionOutcome(
          result: _cancelledResult(),
          shouldRetry: false,
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return _ExecutionOutcome(result: _timeOutResult(), shouldRetry: true);
      }
      if (e.response != null) {
        final statusCode = e.response?.statusCode ?? 0;
        return _ExecutionOutcome(
          result: _handleResponse(e.response!, errorPolicy),
          shouldRetry: statusCode >= 500,
        );
      }
      return _ExecutionOutcome(
        result: _noConnectionResult(),
        shouldRetry: true,
      );
    } catch (_) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _ExecutionOutcome(
          result: _cancelledResult(),
          shouldRetry: false,
        );
      }
      return _ExecutionOutcome(
        result: _noConnectionResult(),
        shouldRetry: true,
      );
    }
  }

  Duration _retryDelay({
    required Duration initialDelay,
    required int attempt,
  }) {
    final multiplier = 1 << (attempt - 1);
    return Duration(
      milliseconds: initialDelay.inMilliseconds * multiplier,
    );
  }

  Future<bool> _waitBeforeRetry({
    required Duration delay,
    required GraphQLCancelToken? cancelToken,
  }) async {
    if (cancelToken == null) {
      await Future.delayed(delay);
      return true;
    }

    await Future.any<void>([
      Future<void>.delayed(delay),
      cancelToken.whenCancelled,
    ]);

    return !cancelToken.isCancelled;
  }

  void _logRetry({
    required String? logContext,
    required int attempt,
    required int totalAttempts,
    required Duration delay,
  }) {
    log?.call(
      '${logContext ?? 'GraphQL request'} - '
      'Attempt $attempt/$totalAttempts failed. '
      'Retrying in ${delay.inSeconds}s.',
      isAlert: true,
    );
  }

  GraphQLQueryResult<Object?> _handleResponse(
    Response<dynamic> response,
    ErrorPolicy? errorPolicy,
  ) {
    if (response.statusCode != 200) {
      return GraphQLQueryResult(
        exception: GraphQLOperationException(
          graphqlErrors: [
            GraphQLError(
              message: response.statusMessage ?? 'HTTP ${response.statusCode}',
              extensions: {'exception_code': response.statusCode.toString()},
            ),
          ],
        ),
      );
    }

    return _parseResponse(response, errorPolicy);
  }
}

class _TimeoutException implements Exception {}

abstract class IGraphQLHelper {
  Future<GraphQLQueryResult<Object?>> query({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    GraphQLRetryOptions? retryOptions,
    String? logContext,
  });

  Future<GraphQLQueryResult<Object?>> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    GraphQLRetryOptions? retryOptions,
    String? logContext,
  });
}

class _ExecutionOutcome {
  final GraphQLQueryResult<Object?> result;
  final bool shouldRetry;

  const _ExecutionOutcome({
    required this.result,
    required this.shouldRetry,
  });
}
