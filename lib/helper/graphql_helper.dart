import 'dart:async';

import 'package:graphql/client.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:http/http.dart' as http;

import 'package:manager_api/helper/cancellable_http_client.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

class GraphQLHelper implements IGraphQLHelper {
  Duration? timeOutDuration;
  GraphQLHelper({this.timeOutDuration});

  DocumentNode _parseDocument(String document) =>
      transform(parseString(document), []);

  Duration get _defaultTimeout => const Duration(seconds: 15);

  GraphQLClient getGraphQLClient({
    String? token,
    Map<String, String>? headers,
    GraphQLCancelToken? cancelToken,
  }) {
    late Link link;
    http.Client? httpClient;

    if (cancelToken != null) {
      httpClient = _createCancellableClient(cancelToken);
    }

    if (headers == null) {
      link = HttpLink(
        "${const String.fromEnvironment("BASEAPIURL")}/graphql",
        defaultHeaders: token != null
            ? {
                "Authorization":
                    "${const String.fromEnvironment("BASETOKENPROJECT")}$token",
              }
            : {},
        httpClient: httpClient,
      );
    } else {
      link = HttpLink(
        headers['apiUrl']!,
        defaultHeaders: headers,
        httpClient: httpClient,
      );
    }

    return GraphQLClient(
      cache: GraphQLCache(),
      link: link,
      queryRequestTimeout: timeOutDuration ?? _defaultTimeout,
    );
  }

  http.Client _createCancellableClient(GraphQLCancelToken cancelToken) {
    return CancellableHttpClient(cancelToken);
  }

  @override
  Future<QueryResult> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    CacheRereadPolicy cacheRereadPolicy = CacheRereadPolicy.ignoreAll,
    FetchPolicy fetchPolicy = FetchPolicy.networkOnly,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledAPI();
    }

    final GraphQLClient client = getGraphQLClient(
      token: token,
      headers: headers,
      cancelToken: cancelToken,
    );

    final MutationOptions options = MutationOptions(
      document: _parseDocument(data),
      variables: variables,
      fetchPolicy: fetchPolicy,
      cacheRereadPolicy: cacheRereadPolicy,
      errorPolicy: errorPolicy,
    );

    return _executeOperation(
      operation: () => client.mutate(options),
      durationTimeOut: durationTimeOut,
      cancelToken: cancelToken,
      keepOriginalOnSocketException: false,
    );
  }

  @override
  Future<QueryResult> query({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
    CacheRereadPolicy cacheRereadPolicy = CacheRereadPolicy.ignoreAll,
    FetchPolicy fetchPolicy = FetchPolicy.networkOnly,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledAPI();
    }

    final GraphQLClient client = getGraphQLClient(
      token: token,
      headers: headers,
      cancelToken: cancelToken,
    );

    final QueryOptions options = QueryOptions(
      document: _parseDocument(data),
      variables: variables,
      fetchPolicy: fetchPolicy,
      cacheRereadPolicy: cacheRereadPolicy,
      errorPolicy: errorPolicy,
    );

    return _executeOperation(
      operation: () => client.query(options),
      durationTimeOut: durationTimeOut,
      cancelToken: cancelToken,
      keepOriginalOnSocketException: true,
    );
  }

  Future<QueryResult> _executeOperation({
    required Future<QueryResult> Function() operation,
    Duration? durationTimeOut,
    GraphQLCancelToken? cancelToken,
    required bool keepOriginalOnSocketException,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledAPI();
    }

    try {
      final Future<QueryResult> opFuture = operation();

      if (cancelToken != null) {
        final QueryResult result = await Future.any<QueryResult>([
          opFuture.timeout(
            durationTimeOut ?? timeOutDuration ?? _defaultTimeout,
            onTimeout: () async => _timeOutAPI(),
          ),
          cancelToken.whenCancelled.then<QueryResult>((_) => _cancelledAPI()),
        ]);

        if (cancelToken.isCancelled) {
          return _cancelledAPI();
        }

        return _processResult(result,
            keepOriginalOnSocketException: keepOriginalOnSocketException);
      } else {
        final QueryResult result = await opFuture.timeout(
          durationTimeOut ?? timeOutDuration ?? _defaultTimeout,
          onTimeout: () async => _timeOutAPI(),
        );

        return _processResult(result,
            keepOriginalOnSocketException: keepOriginalOnSocketException);
      }
    } catch (e) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _cancelledAPI();
      }
      return _noConnectionAPI();
    }
  }

  QueryResult _processResult(QueryResult result,
      {required bool keepOriginalOnSocketException}) {
    if (result.exception == null || result.exception!.linkException == null) {
      return result;
    }

    final String original =
        result.exception!.linkException!.originalException.toString();

    if (!original.contains("SocketException: Failed host lookup")) {
      return _noConnectionAPI();
    }

    return keepOriginalOnSocketException ? result : _timeOutAPI();
  }

  QueryResult _timeOutAPI() => QueryResult(
        source: QueryResultSource.network,
        exception: OperationException(
          graphqlErrors: [const GraphQLError(message: "timeout")],
        ),
        options: QueryOptions(
          document: gql(""),
          operationName: '',
        ),
      );

  QueryResult _noConnectionAPI() => QueryResult(
        source: QueryResultSource.network,
        exception: OperationException(
          graphqlErrors: [const GraphQLError(message: "noConnection")],
        ),
        options: QueryOptions(
          document: gql(""),
          operationName: '',
        ),
      );

  QueryResult _cancelledAPI() => QueryResult(
        source: QueryResultSource.network,
        exception: OperationException(
          graphqlErrors: [const GraphQLError(message: "cancelled")],
        ),
        options: QueryOptions(
          document: gql(""),
          operationName: '',
        ),
      );
}

abstract class IGraphQLHelper {
  Future<QueryResult> query({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
  });

  Future<QueryResult> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
    GraphQLCancelToken? cancelToken,
  });
}
