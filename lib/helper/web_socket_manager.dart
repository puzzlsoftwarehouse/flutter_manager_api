import 'package:manager_api/helper/web_socket_service.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_client/web_socket_client.dart';

abstract class WebSocketManager {
  BehaviorSubject<ResultLR<WebSocketType, dynamic>>? get stream;
  String? get id;
  String? get type;

  WebSocketType get socketType;
  WebSocket? get controller;

  WebSocketManager();

  Future<void> initialize({
    required String url,
    required String token,
  });

  void sendMessage(String message);

  void checkConnection(ConnectionState state);
  Future<void> closeSection();
  void setSocketType(WebSocketType value);
  void debugger(String name);
  void dispose();
}
