class DefaultFailures {
  final String unknownError;
  final String noConnectionError;
  final String timeoutError;
  final String notFoundError;
  final String serverError;
  final String cancelError;

  DefaultFailures({
    this.unknownError = 'Unknown error. Try again or contact support',
    this.noConnectionError = 'No internet connection',
    this.timeoutError = 'The connection has timed out. Try again',
    this.notFoundError = 'What you are looking for was not found',
    this.serverError = 'Could not reach the server. Try again',
    this.cancelError = 'Request canceled',
  });
}
