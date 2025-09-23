enum WebSocketType {
  connected,
  disconnected,
  disconnecting,
  connecting,
  reconnecting,
  reconnected;

  bool get isConnected => this == WebSocketType.connected;
  bool get isDisconnected => this == WebSocketType.disconnected;
  bool get isConnecting => this == WebSocketType.connecting;
  bool get isReconnecting => this == WebSocketType.reconnecting;
  bool get isReconnected => this == WebSocketType.reconnected;
}
