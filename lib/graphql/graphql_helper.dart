import 'dart:async';

import 'package:dio/dio.dart';
import 'package:manager_api/models/graphql/graphql_policies.dart';
import 'package:manager_api/models/graphql/graphql_result.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

class GraphQLHelper implements IGraphQLHelper {
  Duration? timeOutDuration;

  Dio? _dio;

  GraphQLHelper({this.timeOutDuration});

  Duration get _defaultTimeout => const Duration(seconds: 15);

  Dio get _client {
    return _dio!;
  }

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
      );

  Future<GraphQLQueryResult<Object?>> _execute({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledResult();
    }

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
          return _cancelledResult();
        }
      } else {
        result = await resultFuture
            .timeout(timeout, onTimeout: () => throw _TimeoutException())
            .then((r) => _handleResponse(r, errorPolicy));
      }

      return result;
    } on _TimeoutException {
      return _timeOutResult();
    } on DioException catch (e) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _cancelledResult();
      }
      if (e.type == DioExceptionType.cancel) {
        return _cancelledResult();
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return _timeOutResult();
      }
      return _noConnectionResult();
    } catch (_) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _cancelledResult();
      }
      return _noConnectionResult();
    }
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
  });

  Future<GraphQLQueryResult<Object?>> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
  });
}
