import 'dart:async';

class TimerUtils {
  Timer? _timer;
  Timer? _timerRetry;
  int _attempts = 5;

  void updateWithTimer(
    Function() callback, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _timer?.cancel();
    _timer = Timer(duration, callback);
  }

  void cancelTimer() {
    _timer?.cancel();
  }

  void retry(
    Function() function, {
    Duration duration = const Duration(seconds: 5),
  }) {
    if (_attempts <= 0) return;
    _timerRetry = Timer(duration, () {
      _timerRetry?.cancel();
      function();
      _attempts -= 1;
    });
  }
}
