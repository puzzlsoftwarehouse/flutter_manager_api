import 'dart:async';

class GraphQLCancelToken {
  bool _isCancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      if (!_completer.isCompleted) {
        _completer.complete();
      }
    }
  }

  Future<void> get whenCancelled => _completer.future;

  factory GraphQLCancelToken() => GraphQLCancelToken._();

  GraphQLCancelToken._();
}

