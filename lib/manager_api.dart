import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:graphql/client.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/graphql_read.dart';
import 'package:manager_api/helper/graphql_helper.dart';
import 'package:manager_api/models/failure/default_failures.dart';
import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';
import 'package:manager_api/requests/graphql_request.dart';
import 'package:manager_api/helper/rest_helper.dart';
import 'package:manager_api/requests/rest_request.dart';

DefaultFailures managerDefaultAPIFailures = DefaultFailures();

class ManagerAPI {
  final GraphQLHelper _api = GraphQLHelper();
  final RestHelper _restAPI = RestHelper();

  List<Failure> _failures = <Failure>[];

  ManagerAPI({
    List<Failure> failures = const <Failure>[],
    required DefaultFailures defaultFailures,
  }) {
    _failures = DefaultAPIFailures.failures..addAll(failures);
    managerDefaultAPIFailures = defaultFailures;
  }

  Failure getDefaultFailure(String? text) => Failure(
        code: "000",
        message: managerDefaultAPIFailures.unknownError,
        log: text,
      );

  String? getException(List<GraphQLError>? errors) {
    if (errors == null || errors.isEmpty) return null;
    if (errors.first.extensions != null) {
      return errors.first.extensions?['exception_code'].toString();
    }
    return errors.first.message.toString();
  }

  Failure getGraphQLFailure(
      OperationException? exception, List<Failure> failures) {
    log("GraphQL Error", error: exception.toString());
    _failures.addAll(failures);

    if (exception?.linkException != null) {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.noConnectionCode)!;
    }

    String? exceptionCode = getException(exception?.graphqlErrors);

    if (exceptionCode == DefaultAPIFailures.timeoutCode) {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.timeoutCode)!;
    }
    Failure? failure =
        _failures.firstWhereOrNull((failure) => failure.code == exceptionCode);

    return failure ?? getDefaultFailure(exceptionCode);
  }

  Future<QueryResult<Object?>> getCorrectGraphQLRequest(
      GraphQLRequest request) async {
    log(request.variables.toString());

    String query = await GraphQLRead.get(
      path: request.path,
      type: request.type,
      requestName: request.name,
    );

    if (request.type == RequestGraphQLType.mutation) {
      return await _api.mutation(
        data: query,
        token: request.token,
        variables: request.variables,
        durationTimeOut: request.timeOutDuration,
      );
    }
    return await _api.query(
      data: query,
      token: request.token,
      variables: request.variables,
      durationTimeOut: request.timeOutDuration,
    );
  }

  GraphQLRequest convertGraphQLRequest(Map<String, dynamic>? request) =>
      GraphQLRequest.fromJson(request ?? const <String, dynamic>{});

  Future<ResultLR<Failure, dynamic>> request({
    Map<String, dynamic>? request,
    required String named,
  }) async {
    if (request?['typeAPI'] == 'rest') {
      RestRequest requestResult = convertRestRequest(request);
      if (requestResult.skipRequest != null) {
        log("REQUEST SKIPPED: ${requestResult.name}");
        return requestResult.skipRequest!.result;
      }
      Map<String, dynamic>? result = await getCorrectRestRequest(requestResult);
      if (result?['error'] != null) {
        return Left(getRestFailure(result!['error'], requestResult.failures));
      }
      return Right(requestResult.returnRequest(result!));
    }

    GraphQLRequest requestResult = convertGraphQLRequest(request);
    if (requestResult.skipRequest != null) {
      log("REQUEST SKIPPED: ${requestResult.name}");
      return requestResult.skipRequest!.result;
    }

    QueryResult<Object?> result = await getCorrectGraphQLRequest(requestResult);

    if (!result.hasException) {
      return Right(requestResult.returnRequest(result.data!));
    }

    return Left(getGraphQLFailure(result.exception, requestResult.failures));
  }

  Failure getRestFailure(
      Map<String, dynamic> exception, List<Failure> failures) {
    log("Rest Request Error", error: exception.toString());
    _failures.addAll(failures);

    if (exception['type'] == 'noConnection') {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.noConnectionCode)!;
    }
    if (exception['type'] == 'timeout') {
      return DefaultAPIFailures.getFailureByCode(
          DefaultAPIFailures.timeoutCode)!;
    }
    String? code;
    if (exception['code'] is int) {
      code = exception['code'].toString();
    } else {
      code = exception['code'];
    }
    Failure? failure =
        _failures.firstWhereOrNull((failure) => failure.code == code);

    return failure ??
        getDefaultFailure("${code ?? ""}  ${exception['message']}");
  }

  RestRequest convertRestRequest(Map<String, dynamic>? request) =>
      RestRequest.fromJson(request ?? const <String, dynamic>{});

  Future<Map<String, dynamic>?> getCorrectRestRequest(
      RestRequest request) async {
    log(request.body.toString());
    if (request.bodyType == BodyType.bytes) {
      return await _restAPI.sendMedia(
        file: request.body!['file'],
        url: request.url,
        parameters: request.parameters ?? {},
        headers: request.headers,
        streamProgress: request.streamProgress,
        cancelToken: request.cancelToken,
      );
    }

    if (request.type == RequestRestType.get) {
      return await _restAPI.getRequest(
        url: request.url,
        headers: request.headers,
        responseType: request.bodyResponseType == RequestResponseBodyType.bytes
            ? ResponseType.bytes
            : ResponseType.json,
      );
    }
    if (request.type == RequestRestType.post) {
      return await _restAPI.postRequest(
        url: request.url,
        headers: request.headers,
        body: request.body,
      );
    }

    log("REQUEST TYPE REST NOT FOUND");
    return null;
  }
}
