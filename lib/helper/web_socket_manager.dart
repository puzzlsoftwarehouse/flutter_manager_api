import 'package:manager_api/helper/web_socket_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_client/web_socket_client.dart';

abstract class WebSocketManager {
  late BehaviorSubject<dynamic> stream;
  WebSocketType get socketType;

  WebSocket? get controller;

  WebSocketManager({BehaviorSubject<dynamic>? stream});

  Future<bool> initialize({
    required String url,
    required String token,
  });

  void sendMessage(String message);

  void checkConnection();
  void closeSection();
  Future<bool> create({
    required String url,
    required String token,
  });
  void setSocketType(WebSocketType value);
  void debugger(String name);
  void dispose();
}
