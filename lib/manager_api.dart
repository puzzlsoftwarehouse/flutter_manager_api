import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:log_print/log_print.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/graphql_read.dart';
import 'package:manager_api/helper/graphql_helper.dart';
import 'package:manager_api/helper/rest_helper.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:manager_api/helper/web_socket_service.dart';
import 'package:manager_api/models/failure/default_failures.dart';
import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';
import 'package:manager_api/requests/graphql_request.dart';
import 'package:manager_api/requests/rest_request.dart';
import 'package:rxdart/rxdart.dart';

export 'package:manager_api/utils/validate_fragments.dart';

DefaultFailures managerDefaultAPIFailures = DefaultFailures();

mixin class ManagerToken {
  String? token;
}

class ManagerAPI with ManagerToken {
  static String? _token;
  Duration? timeOutDuration;

  late GraphQLHelper _api;
  late RestHelper _restAPI;

  List<Failure> _failures = <Failure>[];
  Map<String, String>? Function(String? token)? headers;

  Map<String, String>? _headerCustom;

  ManagerAPI({
    required DefaultFailures defaultFailures,
    List<Failure> failures = const <Failure>[],
    this.headers,
    this.timeOutDuration,
  }) {
    _failures = DefaultAPIFailures.failures..addAll(failures);
    managerDefaultAPIFailures = defaultFailures;
    _restAPI = RestHelper();
    _api = GraphQLHelper(timeOutDuration: timeOutDuration);
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
    OperationException? exception,
    List<Failure> failures,
  ) {
    generateLog("GraphQL Error: ${exception.toString()}", isError: true);
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
    String query = await GraphQLRead.get(
      path: request.path,
      type: request.type,
      requestName: request.name,
    );

    if (request.type == RequestGraphQLType.mutation) {
      return await _api.mutation(
        data: query,
        token: request.token ?? token,
        headers: getCorrectHeaders(request: request),
        variables: request.variables,
        durationTimeOut: request.timeOutDuration ?? timeOutDuration,
        errorPolicy: request.errorPolicy,
      );
    }

    return await _api.query(
      data: query,
      token: request.token ?? token,
      headers: getCorrectHeaders(request: request),
      variables: request.variables,
      durationTimeOut: request.timeOutDuration ?? timeOutDuration,
      errorPolicy: request.errorPolicy,
    );
  }

  Map<String, String> getCorrectHeaders({
    GraphQLRequest? request,
    RestRequest? restRequest,
  }) {
    Map<String, String> newResult =
        request?.headers ?? restRequest?.headers ?? <String, String>{};
    newResult.addAll(_headerCustom ?? <String, String>{});

    Map<String, String> actualHeaders =
        headers?.call(request?.token ?? token) ?? <String, String>{};

    actualHeaders.addAll(newResult);
    return actualHeaders;
  }

  GraphQLRequest convertGraphQLRequest(Map<String, dynamic>? request) =>
      GraphQLRequest.fromJson(request ?? const <String, dynamic>{});

  Future<ResultLR<Failure, dynamic>> request({
    required String named,
    Map<String, dynamic>? request,
    int? ignoreCode,
  }) async {
    if (request?['typeAPI'] == 'rest') {
      Stopwatch stopwatch = Stopwatch()..start();
      RestRequest requestResult = convertRestRequest(request);
      if (requestResult.skipRequest != null) {
        generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
        return requestResult.skipRequest!.result;
      }
      Map<String, dynamic>? result = await getCorrectRestRequest(requestResult);
      stopwatch.stop();

      generateLog(generateMsg(
        restRequest: requestResult,
        stopwatch: stopwatch,
      ));

      if (result?['error'] != null) {
        return Left(getRestFailure(result!['error'], requestResult.failures));
      }
      return Right(requestResult.returnRequest(result!));
    }

    GraphQLRequest requestResult = convertGraphQLRequest(request);
    if (requestResult.skipRequest != null) {
      generateLog("REQUEST SKIPPED: ${requestResult.name}", isAlert: true);
      return requestResult.skipRequest!.result;
    }

    return await identifyPermissionForRequest(
      requestResult: requestResult,
      ignoreCode: ignoreCode,
    );
  }

  Future<ResultLR<Failure, dynamic>> identifyPermissionForRequest({
    required GraphQLRequest<dynamic> requestResult,
    int? ignoreCode,
  }) async {
    Stopwatch stopwatch = Stopwatch()..start();

    if (ignoreCode != null) {
      requestResult = requestResult.copyWith(errorPolicy: ErrorPolicy.all);
    }

    QueryResult<Object?> result = await getCorrectGraphQLRequest(requestResult);
    stopwatch.stop();

    generateLog(generateMsg(
      requestResult: requestResult,
      stopwatch: stopwatch,
    ));

    if (result.hasException && ignoreCode == null) {
      return Left(getGraphQLFailure(result.exception, requestResult.failures));
    }

    if (result.hasException && ignoreCode != null && result.data == null) {
      return Left(getGraphQLFailure(result.exception, requestResult.failures));
    }

    if (result.hasException && ignoreCode != null && result.data != null) {
      String? exceptionCode = getException(result.exception?.graphqlErrors);

      if (exceptionCode == ignoreCode.toString()) {
        dynamic returned = await requestResult.returnRequest(result.data!);
        return Right(returned);
      }
    }

    if (result.data != null && !result.hasException) {
      dynamic returned = await requestResult.returnRequest(result.data!);
      return Right(returned);
    }

    return Left(getGraphQLFailure(result.exception, requestResult.failures));
  }

  Failure getRestFailure(
    Map<String, dynamic> exception,
    List<Failure> failures,
  ) {
    generateLog("Rest Request Error: ${exception.toString()}", isError: true);
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
    if (request.bodyType == BodyType.bytes) {
      return await _restAPI.sendMedia(
        file: request.body!['file'],
        url: request.url,
        parameters: request.parameters ?? {},
        headers: getCorrectHeaders(restRequest: request),
        streamProgress: request.streamProgress,
        cancelToken: request.cancelToken,
      );
    }

    if (request.type == RequestRestType.get) {
      return await _restAPI.getRequest(
        url: request.url,
        headers: getCorrectHeaders(restRequest: request),
        responseType: request.bodyResponseType == RequestResponseBodyType.bytes
            ? ResponseType.bytes
            : ResponseType.json,
      );
    }

    if (request.type == RequestRestType.post) {
      return await _restAPI.postRequest(
        url: request.url,
        headers: getCorrectHeaders(restRequest: request),
        body: request.body,
      );
    }

    generateLog("REQUEST TYPE REST NOT FOUND", isError: true);
    return null;
  }

  void addInHeader(Map<String, String> header) {
    _headerCustom = {...header};
  }

  String generateMsg({
    RestRequest? restRequest,
    GraphQLRequest<dynamic>? requestResult,
    Stopwatch? stopwatch,
  }) {
    String type = requestResult?.type.toString().split(".").last ??
        restRequest?.type.toString().split(".").last ??
        "".toUpperCase();

    String name = requestResult?.name ?? restRequest?.name ?? "";
    Map<String, dynamic> variables =
        requestResult?.variables ?? restRequest?.body ?? {};

    return """[${requestResult?.path.toUpperCase()}] [$type $name] - $variables - ${stopwatch?.elapsedMilliseconds}ms""";
  }

  void generateLog(
    String body, {
    bool isError = false,
    bool isAlert = false,
  }) {
    if (!kDebugMode) return;

    LogPrint(
      body,
      type: LogPrintType.custom,
      title: "Graphql",
      titleBackgroundColor: isAlert
          ? Colors.yellowAccent
          : isError
              ? Colors.redAccent
              : Colors.amberAccent,
      messageColor: Colors.amberAccent,
    );
  }

  WebSocketManager webSocketService({BehaviorSubject<dynamic>? stream}) =>
      WebSocketService(stream: stream);

  @override
  set token(String? value) {
    _token = value;
    super.token = value;
  }

  @override
  String? get token => _token;
}
