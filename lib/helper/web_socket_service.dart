import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_print/log_print.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:manager_api/models/websocket/web_socket_type.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rxdart/rxdart.dart';

class WebSocketService extends WebSocketManager with ChangeNotifier {
  bool _isClosed = false;
  bool enablePing = true;

  String? _id;
  @override
  String? get id => _id;

  String? _type;
  @override
  String? get type => _type;

  WebSocketChannel? _controller;
  @override
  WebSocketChannel? get controller => _controller;

  String? _url;
  String? _token;

  Timer? _timer;

  bool _pong = false;

  WebSocketType _socketType = WebSocketType.connecting;
  @override
  WebSocketType get socketType => _socketType;

  bool _needReconnect = false;

  WebSocketService({
    String? id,
    required String type,
    BehaviorSubject<SocketEvent>? stream,
  }) {
    _id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    _type = type;
    super.stream = stream ?? BehaviorSubject<SocketEvent>();
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

    setSocketType(WebSocketType.connecting);

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
            stream.add(ConnectionEvent(WebSocketType.reconnected));
          }
          return;
        }
        debugger(event.toString());
        stream.add(MessageEvent(event));
        setSocketType(WebSocketType.connected);
      }, onDone: () {
        stream.add(ConnectionEvent(WebSocketType.disconnected));
        setSocketType(WebSocketType.disconnected);
      });
    } catch (e) {
      debugger("WebSocket Error: $e");
      stream.add(ConnectionEvent(WebSocketType.disconnected));
      setSocketType(WebSocketType.disconnected);
      checkConnection();
      return false;
    }

    debugger("WebSocket Connected: ${_controller != null}");
    stream.add(ConnectionEvent(WebSocketType.connected));
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

          _controller?.sink.close();
          stream.add(ConnectionEvent(WebSocketType.disconnected));
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
    stream.add(ConnectionEvent(WebSocketType.disconnected));
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
    if (kReleaseMode) return;

    LogPrint(
      name,
      type: LogPrintType.custom,
      title: "WebSocket $_type",
      titleBackgroundColor: Colors.greenAccent,
      messageColor: Colors.green,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    closeSection();
    super.dispose();
  }
}
