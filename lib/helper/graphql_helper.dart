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

  DocumentNode gqlPersonalize(String document) =>
      transform(parseString(document), []);

  Duration get _durationTimeOut => const Duration(seconds: 15);

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
      queryRequestTimeout: timeOutDuration ?? _durationTimeOut,
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
      document: gqlPersonalize(data),
      variables: variables,
      fetchPolicy: FetchPolicy.networkOnly,
      errorPolicy: errorPolicy,
    );

    try {
      final Future<QueryResult<Object?>> queryFuture = client.mutate(options);

      if (cancelToken != null) {
        final QueryResult result = await Future.any<QueryResult>([
          queryFuture.timeout(
            durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
            onTimeout: () async => _timeOutAPI(),
          ),
          cancelToken.whenCancelled.then<QueryResult>((_) => _cancelledAPI()),
        ]);

        if (cancelToken.isCancelled) {
          return _cancelledAPI();
        }

        final QueryResult queryResult = result;

        if (queryResult.exception == null ||
            queryResult.exception!.linkException == null) {
          return queryResult;
        }

        if (!queryResult.exception!.linkException!.originalException
            .toString()
            .contains("SocketException: Failed host lookup")) {
          return _noConnectionAPI();
        }

        return _timeOutAPI();
      } else {
        final QueryResult result = await queryFuture.timeout(
          durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
          onTimeout: () async => _timeOutAPI(),
        );

        if (result.exception == null ||
            result.exception!.linkException == null) {
          return result;
        }

        if (!result.exception!.linkException!.originalException
            .toString()
            .contains("SocketException: Failed host lookup")) {
          return _noConnectionAPI();
        }

        return _timeOutAPI();
      }
    } catch (e) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _cancelledAPI();
      }
      return _noConnectionAPI();
    }
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
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledAPI();
    }

    try {
      final GraphQLClient client = getGraphQLClient(
        token: token,
        headers: headers,
        cancelToken: cancelToken,
      );

      final QueryOptions options = QueryOptions(
        document: gqlPersonalize(data),
        variables: variables,
        fetchPolicy: FetchPolicy.networkOnly,
        cacheRereadPolicy: CacheRereadPolicy.ignoreAll,
        errorPolicy: errorPolicy,
      );

      final Future<QueryResult<Object?>> queryFuture = client.query(options);

      if (cancelToken != null) {
        final QueryResult result = await Future.any<QueryResult>([
          queryFuture.timeout(
            durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
            onTimeout: () async => _timeOutAPI(),
          ),
          cancelToken.whenCancelled.then<QueryResult>((_) => _cancelledAPI()),
        ]);

        if (cancelToken.isCancelled) {
          return _cancelledAPI();
        }

        final QueryResult queryResult = result;

        if (queryResult.exception == null ||
            queryResult.exception!.linkException == null) {
          return queryResult;
        }

        if (!queryResult.exception!.linkException!.originalException
            .toString()
            .contains("SocketException: Failed host lookup")) {
          return _noConnectionAPI();
        }

        return queryResult;
      } else {
        final QueryResult result = await queryFuture.timeout(
          durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
          onTimeout: () async => _timeOutAPI(),
        );

        if (result.exception == null ||
            result.exception!.linkException == null) {
          return result;
        }

        if (!result.exception!.linkException!.originalException
            .toString()
            .contains("SocketException: Failed host lookup")) {
          return _noConnectionAPI();
        }

        return result;
      }
    } catch (e) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return _cancelledAPI();
      }
      return _noConnectionAPI();
    }
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
