import 'package:graphql/client.dart';

import 'package:gql/ast.dart';

import 'package:gql/language.dart';
import 'package:manager_api/manager_api.dart';

class GraphQLHelper implements IGraphQLHelper {
  Map<ManagerHeader, String>? options;
  GraphQLHelper(this.options);

  DocumentNode gqlPersonalize(String document) =>
      transform(parseString(document), []);

  Duration get _durationTimeOut => const Duration(seconds: 15);

  GraphQLClient getGraphQLClient({String? token}) {
    String? baseApiUrl = options?[ManagerHeader.apiUrl];
    String? baseToken = options?[ManagerHeader.tokenProject];

    final Link link = HttpLink(
      "${baseApiUrl ?? const String.fromEnvironment("BASEAPIURL")}/graphql",
      defaultHeaders: token != null
          ? {
              "Authorization":
                  "${baseToken ?? const String.fromEnvironment("BASETOKENPROJECT")}$token",
            }
          : {},
    );

    return GraphQLClient(
      cache: GraphQLCache(),
      link: link,
    );
  }

  @override
  Future<QueryResult> mutation({
    required String data,
    String? token,
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
  }) async {
    final GraphQLClient client = getGraphQLClient(
      token: token,
    );

    final MutationOptions options = MutationOptions(
      document: gqlPersonalize(data),
      variables: variables,
      fetchPolicy: FetchPolicy.networkOnly,
      errorPolicy: errorPolicy,
    );

    try {
      final QueryResult result = await client.mutate(options).timeout(
            durationTimeOut ?? _durationTimeOut,
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
    Map<String, dynamic> variables = const {},
    Duration? durationTimeOut,
    ErrorPolicy? errorPolicy,
  }) async {
    try {
      final GraphQLClient client = getGraphQLClient(token: token);

      final QueryOptions options = QueryOptions(
        document: gqlPersonalize(data),
        variables: variables,
        fetchPolicy: FetchPolicy.networkOnly,
        cacheRereadPolicy: CacheRereadPolicy.ignoreAll,
        errorPolicy: errorPolicy,
      );

      final QueryResult result = await client.query(options).timeout(
            durationTimeOut ?? _durationTimeOut,
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
