import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:log_print/log_print.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_client/web_socket_client.dart';

enum WebSocketType { connected, disconnected, trying }

class WebSocketService extends WebSocketManager with ChangeNotifier {
  WebSocket? _controller;
  @override
  WebSocket? get controller => _controller;

  String? _url;

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
    setSocketType(WebSocketType.trying);

    try {
      String beforeString = url.contains("?") ? "&" : "?";

      _controller?.close();
      _controller = null;
      _controller = WebSocket(
        Uri.parse("$url${beforeString}token=$token"),
        backoff: ConstantBackoff(Duration(seconds: 5)),
        pingInterval: Duration(seconds: 5),
      );

      _controller!.connection.listen((state) => checkConnection(state));

      _controller!.messages.listen((event) {
        try {
          if (jsonDecode(event)?['data'] != null) {
            Map<String, dynamic> result = jsonDecode(event);
            (result['data'] as Map<String, dynamic>?)
                ?.removeWhere((key, value) => value == null || value == '');

            debugger(result.toString());
            stream.add(jsonEncode(result));
          }
        } catch (_) {
          debugger("$event");
          stream.add(event);
          setSocketType(WebSocketType.connected);
        }
      }, onDone: () {
        stream.add("disconnected");
        setSocketType(WebSocketType.disconnected);
      });
    } catch (e) {
      debugger("WebSocket Error: $e");
      stream.add("disconnected");
      setSocketType(WebSocketType.disconnected);
      return false;
    }

    return _controller != null;
  }

  @override
  void checkConnection(ConnectionState state) {
    if (state is Connecting) {
      debugger("Connecting... $_url");
      setSocketType(WebSocketType.trying);
    }

    if (state is Connected) {
      debugger("Connected... $_url");
      stream.add("connected");
      setSocketType(WebSocketType.connected);
    }

    if (state is Reconnecting) {
      debugger("Reconnecting... $_url");
      setSocketType(WebSocketType.trying);
    }

    if (state is Reconnected) {
      debugger("Reconnected... $_url");
      stream.add("connected");
      setSocketType(WebSocketType.connected);
    }

    if (state is Disconnected) {
      debugger("Disconnected... $_url");
      stream.add("disconnected");
      setSocketType(WebSocketType.disconnected);
    }
  }

  @override
  void sendMessage(String message) {
    _controller?.send(message);
  }

  @override
  void closeSection() {
    stream.add("disconnected");
    setSocketType(WebSocketType.disconnected);

    _controller?.close();
    _controller = null;
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
    LogPrint(
      name,
      type: LogPrintType.custom,
      title: "WebSocket",
      titleBackgroundColor: Colors.greenAccent,
      messageColor: Colors.green,
    );
  }

  @override
  void dispose() {
    closeSection();
    super.dispose();
  }
}
