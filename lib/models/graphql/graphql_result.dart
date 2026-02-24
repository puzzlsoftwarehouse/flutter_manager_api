class GraphQLError {
  final String message;
  final Map<String, dynamic>? extensions;

  const GraphQLError({required this.message, this.extensions});

  @override
  String toString() => message;
}

class GraphQLLinkException {
  final Object originalException;

  GraphQLLinkException(this.originalException);

  @override
  String toString() => originalException.toString();
}

class GraphQLOperationException {
  final List<GraphQLError> graphqlErrors;
  final GraphQLLinkException? linkException;

  GraphQLOperationException({
    required this.graphqlErrors,
    this.linkException,
  });
}

enum QueryResultSource { network }

class GraphQLQueryResult<T> {
  final T? data;
  final GraphQLOperationException? exception;
  final QueryResultSource source;

  GraphQLQueryResult({
    this.data,
    this.exception,
    this.source = QueryResultSource.network,
  });

  bool get hasException => exception != null;
}
