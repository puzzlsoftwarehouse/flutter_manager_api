import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rxdart/rxdart.dart';

enum WebSocketType { connected, disconnected, trying }

class WebSocketService extends WebSocketManager with ChangeNotifier {
  bool _isClosed = false;
  bool enablePing = true;

  WebSocketChannel? _controller;
  @override
  WebSocketChannel? get controller => _controller;

  String? _url;
  String? _token;

  Timer? _timer;

  bool _pong = false;

  WebSocketType _socketType = WebSocketType.trying;
  @override
  WebSocketType get socketType => _socketType;

  bool _needReconnect = false;

  WebSocketService({BehaviorSubject<dynamic>? stream}) {
    super.stream = stream ?? BehaviorSubject();
  }

  @override
  Future<bool> initialize({
    required String url,
    required String token,
    bool enablePing = true,
  }) async {
    this.enablePing = enablePing;

    _url = url;
    _token = token;

    if (_isClosed) return false;

    setSocketType(WebSocketType.trying);

    try {
      String beforeString = url.contains("?") ? "&" : "?";

      _controller?.sink.close();
      _controller = null;
      _controller = WebSocketChannel.connect(
          Uri.parse("$url${beforeString}token=$token"));

      checkConnection();

      _controller!.stream.listen((event) {
        if (jsonDecode(event)['type'] == "pong") {
          _pong = true;
          if (_needReconnect) {
            _needReconnect = false;
            stream.add("reconnected");
          }
          return;
        }
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

    debugger("WebSocket Connected: ${_controller != null}");
    stream.add("connected");
    setSocketType(WebSocketType.connected);
    return _controller != null;
  }

  @override
  void checkConnection() {
    if (!enablePing) return;
    if (_controller == null || _isClosed) return;

    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_controller == null) {
        _cancelTimer();
        return;
      }
      if (!enablePing) {
        _cancelTimer();
        return;
      }

      _controller!.sink.add(jsonEncode({"type": "ping"}));
      _pong = false;

      Future.delayed(Duration(seconds: 5), () {
        if (!_pong && !_isClosed) {
          if (_url == null || _token == null) return;
          debugger("WebSocket Disconnected  Don`t have pong");
          stream.add("disconnected");
          setSocketType(WebSocketType.disconnected);

          _cancelTimer();
          _needReconnect = true;
          initialize(url: _url!, token: _token!);
          return;
        }
        if (_isClosed) {
          _cancelTimer();
        }
      });
    });
  }

  @override
  void sendMessage(String message) {
    if (_controller == null || _isClosed) return;
    _controller!.sink.add(message);
  }

  @override
  void closeSection() {
    debugger("WebSocket Disconnected $_url");
    stream.add("disconnected");
    setSocketType(WebSocketType.disconnected);

    _controller?.sink.close();
    _isClosed = true;
    _cancelTimer();
    _controller = null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<bool> create({
    required String url,
    required String token,
    bool enablePing = true,
  }) async {
    bool success = await initialize(
      url: url,
      token: token,
      enablePing: enablePing,
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
