import 'package:manager_api/models/websocket/web_socket_type.dart';

abstract class SocketEvent {}

class MessageEvent extends SocketEvent {
  final dynamic message;
  MessageEvent(this.message);
}

class ConnectionEvent extends SocketEvent {
  final WebSocketType type;
  ConnectionEvent(this.type);
}
