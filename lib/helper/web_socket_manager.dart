import 'package:manager_api/helper/web_socket_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class WebSocketManager {
  late BehaviorSubject<dynamic> stream;
  WebSocketType get socketType;

  WebSocketChannel? get controller;

  WebSocketManager({BehaviorSubject<dynamic>? stream});

  Future<bool> initialize({
    required String url,
    required String token,
    bool enablePing = true,
  });

  void sendMessage(String message);

  void checkConnection();
  void closeSection();
  Future<bool> create({
    required String url,
    required String token,
    bool enablePing = true,
  });
  void setSocketType(WebSocketType value);
  void debugger(String name);
  void dispose();
}
