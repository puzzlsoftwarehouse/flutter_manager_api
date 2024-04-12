import 'package:manager_api/models/failure/failure.dart';

class DefaultFailures {
  final FailureDefault unknownError;
  final FailureDefault noConnectionError;
  final FailureDefault timeoutError;
  final FailureDefault notFoundError;
  final FailureDefault serverError;
  final FailureDefault cancelError;

  DefaultFailures({
    FailureDefault? unknownError,
    FailureDefault? noConnectionError,
    FailureDefault? timeoutError,
    FailureDefault? notFoundError,
    FailureDefault? serverError,
    FailureDefault? cancelError,
  })  : unknownError = unknownError ??
            FailureDefault(
                title: '', message: "Unknown error, contact our support"),
        noConnectionError = noConnectionError ??
            FailureDefault(title: '', message: "No Internet access!"),
        timeoutError = timeoutError ??
            FailureDefault(title: '', message: "The connection has timed out!"),
        notFoundError = notFoundError ??
            FailureDefault(
                title: '', message: "What you are looking for was not found"),
        serverError = serverError ??
            FailureDefault(
                title: '',
                message:
                    "Sorry, we had problems connecting to servers, try again"),
        cancelError = cancelError ??
            FailureDefault(title: '', message: "Request canceled");
}

class FailureDefault {
  final String title;
  final String message;

  FailureDefault({
    required this.title,
    required this.message,
  });
}
