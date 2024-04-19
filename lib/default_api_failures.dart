import 'package:collection/collection.dart';
import 'package:manager_api/manager_api.dart';
import 'package:manager_api/models/failure/failure.dart';

class DefaultAPIFailures {
  DefaultAPIFailures._();
  static Failure _failure(
    String code, {
    String? title,
    required String message,
    String? log,
  }) =>
      Failure(
        code: code,
        title: title,
        message: message,
        log: log,
      );

  static Failure? getFailureByCode(String code) =>
      failures.firstWhereOrNull((failure) => failure.code == code);

  static const String timeoutCode = 'timeout';
  static const String noConnectionCode = 'noConnection';
  static const String unknownErrorCode = '000';
  static const String serverErrorCode = 'server';
  static const String notFoundErrorCode = 'notFound';
  static const String cancelErrorCode = 'cancel';
  static String unknownErrorMessage =
      managerDefaultAPIFailures.unknownError.message;

  static List<Failure> get failures => [
        _failure(
          timeoutCode,
          title: managerDefaultAPIFailures.timeoutError.title,
          message: managerDefaultAPIFailures.timeoutError.message,
        ),
        _failure(
          noConnectionCode,
          title: managerDefaultAPIFailures.noConnectionError.title,
          message: managerDefaultAPIFailures.noConnectionError.message,
        ),
        _failure(
          unknownErrorCode,
          title: managerDefaultAPIFailures.unknownError.title,
          message: unknownErrorMessage,
        ),
        _failure(
          notFoundErrorCode,
          title: managerDefaultAPIFailures.notFoundError.title,
          message: managerDefaultAPIFailures.notFoundError.message,
        ),
        _failure(
          serverErrorCode,
          title: managerDefaultAPIFailures.serverError.title,
          message: managerDefaultAPIFailures.serverError.message,
        ),
        _failure(
          cancelErrorCode,
          title: managerDefaultAPIFailures.cancelError.title,
          message: managerDefaultAPIFailures.cancelError.message,
        ),
      ];

  static bool isNoConnection(Failure failure) =>
      failure.code == noConnectionCode;

  static bool isTimeOut(Failure failure) => failure.code == timeoutCode;

  static bool isNoConnectionOrTimeOut(Failure failure) =>
      isNoConnection(failure) || isTimeOut(failure);

  static Failure get timeOutFailure => getFailureByCode(timeoutCode)!;
  static Failure get noConnectionFailure => getFailureByCode(noConnectionCode)!;
}
