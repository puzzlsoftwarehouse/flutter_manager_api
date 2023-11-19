class DefaultFailures {
  final String unknownError;
  final String noConnectionError;
  final String timeoutError;
  final String notFoundError;
  final String serverError;
  final String cancelError;

  DefaultFailures({
    this.unknownError = "Unknown error, contact our support",
    this.noConnectionError = "No Internet access!",
    this.timeoutError = "The connection has timed out!",
    this.notFoundError = "What you are looking for was not found",
    this.serverError =
        "Sorry, we had problems connecting to servers, try again",
    this.cancelError = "Request canceled",
  });
}
