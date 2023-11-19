import 'package:collection/collection.dart';
import 'package:manager_api/manager_api.dart';
import 'package:manager_api/models/failure/failure.dart';

class DefaultAPIFailures {
  DefaultAPIFailures._();
  static Failure _failure(
    String code, {
    required String message,
    String? log,
  }) =>
      Failure(
        code: code,
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
  static String unknownErrorMessage = managerDefaultAPIFailures.unknownError;

  static List<Failure> get failures => [
        _failure(
          timeoutCode,
          message: managerDefaultAPIFailures.timeoutError,
        ),
        _failure(
          noConnectionCode,
          message: managerDefaultAPIFailures.noConnectionError,
        ),
        _failure(
          unknownErrorCode,
          message: unknownErrorMessage,
        ),
        _failure(
          notFoundErrorCode,
          message: managerDefaultAPIFailures.notFoundError,
        ),
        _failure(
          serverErrorCode,
          message: managerDefaultAPIFailures.serverError,
        ),
        _failure(
          cancelErrorCode,
          message: managerDefaultAPIFailures.cancelError,
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
