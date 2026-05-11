abstract final class WebSocketConstants {
  static const bool loggerEnabled =
      bool.fromEnvironment('WEBSOCKETLOGGER', defaultValue: true);

  static const Duration connectionConfirmationDelay = Duration(seconds: 1);

  static const Duration connectionConfirmationTimeout =
      Duration(seconds: 5);

  static const Duration reconnectBaseDelay = Duration(seconds: 1);

  static const Duration reconnectMaxDelay = Duration(seconds: 30);

  static const Duration pingInterval = Duration(seconds: 10);

  static const Duration pongWait = Duration(seconds: 5);

  static const String pingPayloadJson = '{"type":"ping"}';

  static const int reconnectBackoffClamp = 5;

  static const double reconnectJitterFactor = 0.3;
}
