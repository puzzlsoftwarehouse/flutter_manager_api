import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/models/graphql/graphql_policies.dart';
import 'package:manager_api/models/graphql/graphql_retry_options.dart';
import 'package:manager_api/requests/request_api.dart';
import 'package:manager_api/utils/graphql_cancel_token.dart';

enum RequestGraphQLType { query, mutation, subscription }

class GraphQLRequest<ResultLR> extends RequestAPI<ResultLR> {
  final String path;
  final RequestGraphQLType type;
  final String? token;
  final Map<String, String>? headers;
  final Map<String, dynamic> variables;
  final Duration? timeOutDuration;
  final ErrorPolicy? errorPolicy;
  final CacheRereadPolicy? cacheRereadPolicy;
  final FetchPolicy? fetchPolicy;
  final GraphQLCancelToken? cancelToken;
  final String? query;
  final GraphQLRetryOptions? retryOptions;

  GraphQLRequest({
    required this.path,
    required super.name,
    required this.type,
    required super.returnRequest,
    this.token,
    this.headers,
    this.variables = const {},
    this.timeOutDuration,
    this.errorPolicy,
    this.cacheRereadPolicy,
    this.fetchPolicy,
    this.cancelToken,
    this.query,
    this.retryOptions,
    List<Failure> failures = const <Failure>[],
    super.skipRequest,
  });

  GraphQLRequest copyWith({
    String? path,
    String? name,
    String? token,
    RequestGraphQLType? type,
    Map<String, String>? headers,
    Map<String, dynamic>? variables,
    Duration? timeOutDuration,
    ErrorPolicy? errorPolicy,
    FetchPolicy? fetchPolicy,
    CacheRereadPolicy? cacheRereadPolicy,
    GraphQLCancelToken? cancelToken,
    List<Failure>? failures,
    String? query,
    GraphQLRetryOptions? retryOptions,
  }) {
    return GraphQLRequest(
      path: path ?? this.path,
      name: name ?? super.name,
      token: token ?? this.token,
      type: type ?? this.type,
      headers: headers ?? this.headers,
      variables: variables ?? this.variables,
      timeOutDuration: timeOutDuration ?? this.timeOutDuration,
      errorPolicy: errorPolicy ?? this.errorPolicy,
      cancelToken: cancelToken ?? this.cancelToken,
      failures: failures ?? super.failures,
      cacheRereadPolicy: cacheRereadPolicy ?? this.cacheRereadPolicy,
      fetchPolicy: fetchPolicy ?? this.fetchPolicy,
      returnRequest: returnRequest,
      skipRequest: skipRequest,
      query: query ?? this.query,
      retryOptions: retryOptions ?? this.retryOptions,
    );
  }

  static RequestGraphQLType _typeFromJson(dynamic v) {
    if (v is RequestGraphQLType) return v;
    final s = v?.toString();
    if (s == 'mutation') return RequestGraphQLType.mutation;
    if (s == 'subscription') return RequestGraphQLType.subscription;
    return RequestGraphQLType.query;
  }

  static GraphQLRetryOptions? _retryOptionsFromJson(dynamic value) {
    if (value is Map) {
      return GraphQLRetryOptions.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  factory GraphQLRequest.fromJson(Map<String, dynamic> json) => GraphQLRequest(
        path: json['path'],
        name: json['name'],
        token: json['token'],
        type: _typeFromJson(json['type']),
        headers: json['headers'] != null
            ? Map<String, String>.from(json['headers'] as Map)
            : null,
        variables: json['variables'] != null
            ? Map<String, dynamic>.from(json['variables'] as Map)
            : const {},
        errorPolicy: json['errorPolicy'],
        failures: json['failures'],
        returnRequest: json['returnRequest'],
        skipRequest: json['skipRequest'],
        cacheRereadPolicy: json['cacheRereadPolicy'],
        fetchPolicy: json['fetchPolicy'],
        timeOutDuration: json['timeOutDuration'] != null
            ? Duration(seconds: json['timeOutDuration'])
            : null,
        cancelToken: json['cancelToken'],
        query: json['query'],
        retryOptions: _retryOptionsFromJson(json['retryOptions']),
      );

  @override
  Map<String, dynamic> get toJson => {
        "path": path,
        "name": name,
        "token": token,
        "type": type,
        "headers": headers,
        "variables": variables,
        "timeOutDuration": timeOutDuration?.inSeconds,
        "errorPolicy": errorPolicy,
        "cancelToken": cancelToken,
        "failures": failures,
        "returnRequest": returnRequest,
        "skipRequest": skipRequest,
        "cacheRereadPolicy": cacheRereadPolicy,
        "fetchPolicy": fetchPolicy,
        "query": query,
        "retryOptions": retryOptions?.toJson,
      };
}
