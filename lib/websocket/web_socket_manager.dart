import 'package:manager_api/models/websocket/web_socket_type.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class SocketEvent {}

class MessageEvent extends SocketEvent {
  final dynamic message;
  MessageEvent(this.message);
}

class ConnectionEvent extends SocketEvent {
  final WebSocketType type;
  ConnectionEvent(this.type);
}

abstract class WebSocketManager {
  late BehaviorSubject<SocketEvent> stream;
  String? get id;
  String? get type;
  WebSocketType get socketType;

  WebSocketChannel? get controller;

  WebSocketManager({BehaviorSubject<SocketEvent>? stream});

  Future<bool> initialize({
    required String url,
    bool enablePing = true,
    Map<String, dynamic>? parameters,
  });

  void sendMessage(String message);

  void checkConnection();
  void closeSection();
  Future<bool> create({
    required String url,
    bool enablePing = true,
    Map<String, dynamic>? parameters,
  });
  void setSocketType(WebSocketType value);
  void debugger(String name);
  void dispose();
}
