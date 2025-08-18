import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_client/web_socket_client.dart';

enum WebSocketType { connected, disconnected, trying }

class WebSocketService extends WebSocketManager with ChangeNotifier {
  bool _isClosed = false;

  WebSocket? _controller;
  @override
  WebSocket? get controller => _controller;

  String? _url;
  String? _token;

  Timer? _timer;

  WebSocketType _socketType = WebSocketType.trying;
  @override
  WebSocketType get socketType => _socketType;

  WebSocketService({BehaviorSubject<dynamic>? stream}) {
    super.stream = stream ?? BehaviorSubject();
  }

  @override
  Future<bool> initialize({
    required String url,
    required String token,
  }) async {
    _url = url;
    _token = token;

    if (_isClosed) return false;

    setSocketType(WebSocketType.trying);

    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 5), (_) => checkConnection());

    try {
      String beforeString = url.contains("?") ? "&" : "?";

      _controller?.close();
      _controller = null;
      _controller = WebSocket(
        Uri.parse("$url${beforeString}token=$token"),
        backoff: LinearBackoff(
          initial: Duration(seconds: 0),
          increment: Duration(seconds: 1),
          maximum: Duration(seconds: 5),
        ),
        pingInterval: Duration(seconds: 5),
      );

      checkConnection();

      _controller!.messages.listen((event) {
        debugger("Recebendo dados do WebSocket: $event");

        stream.add(event);
        setSocketType(WebSocketType.connected);
      }, onDone: () {
        stream.add("disconnected");
        setSocketType(WebSocketType.disconnected);
      });
    } catch (e) {
      debugger("WebSocket Error: $e");
      stream.add("disconnected");
      setSocketType(WebSocketType.disconnected);
      checkConnection();
      return false;
    }

    return _controller != null;
  }

  @override
  void checkConnection() {
    if (_controller == null || _isClosed) return;
    final ConnectionState? connectionState = _controller?.connection.state;

    if (connectionState is Connected) {
      debugger("WebSocket Connected");
      stream.add("connected");
      setSocketType(WebSocketType.connected);
    }

    if (connectionState is Reconnecting) {
      debugger("WebSocket Reconnecting...");
      setSocketType(WebSocketType.trying);
      initialize(url: _url!, token: _token!);
    }

    if (connectionState is Disconnected) {
      debugger("WebSocket Disconnected");
      stream.add("disconnected");
      setSocketType(WebSocketType.disconnected);
      initialize(url: _url!, token: _token!);
    }

    if (connectionState is Reconnected) {
      debugger("WebSocket Reconnected");
      stream.add("connected");
      setSocketType(WebSocketType.connected);
      initialize(url: _url!, token: _token!);
    }
  }

  @override
  void sendMessage(String message) {
    if (_controller == null || _isClosed) return;
    _controller!.send(message);
  }

  @override
  void closeSection() {
    debugger("WebSocket Disconnected $_url");
    stream.add("disconnected");
    setSocketType(WebSocketType.disconnected);

    _controller?.close();
    _isClosed = true;
    _controller = null;
    _timer?.cancel();
  }

  @override
  Future<bool> create({
    required String url,
    required String token,
  }) async {
    bool success = await initialize(
      url: url,
      token: token,
    );

    return success;
  }

  @override
  void setSocketType(WebSocketType value) {
    _socketType = value;
    notifyListeners();
  }

  @override
  void debugger(String name) {
    return log(name, name: "WEBSOCKET");
  }

  @override
  void dispose() {
    _timer?.cancel();
    closeSection();
    super.dispose();
  }
}
