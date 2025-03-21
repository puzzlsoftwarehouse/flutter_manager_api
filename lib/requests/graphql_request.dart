import 'package:graphql/client.dart';
import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/requests/request_api.dart';

enum RequestGraphQLType { query, mutation, subscription }

class GraphQLRequest<ResultLR> extends RequestAPI<ResultLR> {
  /// directory where is the file .graphql
  final String path;
  final RequestGraphQLType type;
  final String? token;
  final Map<String, String>? headers;
  final Map<String, dynamic> variables;
  final Duration? timeOutDuration;
  final ErrorPolicy? errorPolicy;

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
    List<Failure>? failures,
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
      failures: failures ?? super.failures,
      returnRequest: returnRequest,
      skipRequest: skipRequest,
    );
  }

  factory GraphQLRequest.fromJson(Map<String, dynamic> json) => GraphQLRequest(
        path: json['path'],
        name: json['name'],
        token: json['token'],
        type: json['type'],
        headers: json['headers'],
        variables: json['variables'],
        errorPolicy: json['errorPolicy'],
        failures: json['failures'],
        returnRequest: json['returnRequest'],
        skipRequest: json['skipRequest'],
        timeOutDuration: json['timeOutDuration'] != null
            ? Duration(seconds: json['timeOutDuration'])
            : null,
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
        "failures": failures,
        "returnRequest": returnRequest,
        "skipRequest": skipRequest,
      };
}
