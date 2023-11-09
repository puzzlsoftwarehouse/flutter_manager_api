import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/requests/request_api.dart';

enum RequestGraphQLType { query, mutation, subscription }

class GraphQLRequest<ResultLR> extends RequestAPI<ResultLR> {
  /// directory where is the file .graphql
  final String path;
  final RequestGraphQLType type;
  final String? token;
  final Map<String, dynamic> variables;

  GraphQLRequest({
    required this.path,
    required super.name,
    required this.type,
    required super.returnRequest,
    this.token,
    this.variables = const {},
    List<Failure> failures = const <Failure>[],
    super.skipRequest,
  });

  factory GraphQLRequest.fromJson(Map<String, dynamic> json) => GraphQLRequest(
        path: json['path'],
        name: json['name'],
        token: json['token'],
        type: json['type'],
        variables: json['variables'],
        failures: json['failures'],
        returnRequest: json['returnRequest'],
        skipRequest: json['skipRequest'],
      );

  @override
  Map<String, dynamic> get toJson => {
        "path": path,
        "name": name,
        "token": token,
        "type": type,
        "variables": variables,
        "failures": failures,
        "returnRequest": returnRequest,
        "skipRequest": skipRequest,
      };
}
