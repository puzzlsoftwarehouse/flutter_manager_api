import 'dart:async';

import 'package:graphql/client.dart';

import 'package:gql/ast.dart';

import 'package:gql/language.dart';

class GraphQLHelper implements IGraphQLHelper {
  Duration? timeOutDuration;
  GraphQLHelper({this.timeOutDuration});
  DocumentNode gqlPersonalize(String document) =>
      transform(parseString(document), []);

  Duration get _durationTimeOut => const Duration(seconds: 15);

  GraphQLClient getGraphQLClient({
    String? token,
    Map<String, String>? headers,
  }) {
    late Link link;

    if (headers == null) {
      link = HttpLink(
        "${const String.fromEnvironment("BASEAPIURL")}/graphql",
        defaultHeaders: token != null
            ? {
                "Authorization":
                    "${const String.fromEnvironment("BASETOKENPROJECT")}$token",
              }
            : {},
      );
    } else {
      link = HttpLink(
        headers['apiUrl']!,
        defaultHeaders: headers,
      );
    }

    return GraphQLClient(
      cache: GraphQLCache(),
      link: link,
      queryRequestTimeout: timeOutDuration ?? _durationTimeOut,
    );
  }

  @override
  Future<QueryResult> mutation({
    required String data,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
  }) async {
    final GraphQLClient client = getGraphQLClient(
      token: token,
      headers: headers,
    );

    final MutationOptions options = MutationOptions(
      document: gqlPersonalize(data),
      variables: variables,
      fetchPolicy: FetchPolicy.networkOnly,
      errorPolicy: errorPolicy,
    );

    try {
      final QueryResult result = await client.mutate(options).timeout(
            durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
            onTimeout: () async => _timeOutAPI(),
          );

      if (result.exception == null || result.exception!.linkException == null) {
        return result;
      }

      if (!result.exception!.linkException!.originalException
          .toString()
          .contains("SocketException: Failed host lookup")) {
        return _noConnectionAPI();
      }

      return _timeOutAPI();
    } catch (e) {
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
  }) async {
    try {
      final GraphQLClient client = getGraphQLClient(
        token: token,
        headers: headers,
      );

      final QueryOptions options = QueryOptions(
        document: gqlPersonalize(data),
        variables: variables,
        fetchPolicy: FetchPolicy.networkOnly,
        cacheRereadPolicy: CacheRereadPolicy.ignoreAll,
        errorPolicy: errorPolicy,
      );

      final QueryResult result = await client.query(options).timeout(
            durationTimeOut ?? timeOutDuration ?? _durationTimeOut,
            onTimeout: () async => _timeOutAPI(),
          );

      if (result.exception == null || result.exception!.linkException == null) {
        return result;
      }

      if (!result.exception!.linkException!.originalException
          .toString()
          .contains("SocketException: Failed host lookup")) {
        return _noConnectionAPI();
      }

      return result;
    } catch (e) {
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
}

abstract class IGraphQLHelper {
  Future<QueryResult> query({
    required String data,
    String? token,
  });

  Future<QueryResult> mutation({
    required String data,
    String? token,
  });
}
