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

  Timer? _timerOfConfirmationHasConnected;

  String? _url;
  Map<String, dynamic>? _parameters;

  Timer? _timer;

  StreamSubscription? _streamSubscription;

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
    Map<String, dynamic>? parameters,
    bool enablePing = true,
  }) async {
    this.enablePing = enablePing;

    _url = url;
    _parameters = parameters;

    if (_isClosed) return false;

    setSocketType(WebSocketType.connecting);

    try {
      _streamSubscription?.cancel();
      _streamSubscription = null;
      _controller?.sink.close();
      _controller = null;
      Uri uri = Uri.parse(url);
      final Map<String, dynamic> queryParameters = {
        ...uri.queryParameters,
        ...?parameters
      };
      uri = uri.replace(queryParameters: queryParameters);
      _controller = WebSocketChannel.connect(uri);

      checkConnection();

      _streamSubscription = _controller!.stream.listen((event) {
        if (jsonDecode(event)['type'] == "pong") {
          _pong = true;
          return;
        }
        debugger(event.toString());
        stream.add(MessageEvent(event));
        setSocketType(WebSocketType.connected);
      }, onDone: () {
        disconnect();
      });
    } catch (e) {
      debugger("WebSocket Error: $e");
      disconnect();
      checkConnection();
      return false;
    }
    connecting();
    confirmationOfConnection();
    return _controller != null;
  }

  void disconnect() {
    debugger("WebSocket Disconnected $_url");
    stream.add(ConnectionEvent(WebSocketType.disconnected));
    setSocketType(WebSocketType.disconnected);

    _timerOfConfirmationHasConnected?.cancel();
    _timerOfConfirmationHasConnected = null;
  }

  void connecting() {
    debugger("WebSocket Connecting: $_url");
    stream.add(ConnectionEvent(WebSocketType.connecting));
    setSocketType(WebSocketType.connecting);
  }

  void confirmationOfConnection() {
    _timerOfConfirmationHasConnected?.cancel();
    _timerOfConfirmationHasConnected = Timer(Duration(seconds: 1), () {
      if (_needReconnect) {
        debugger("WebSocket Reconnected: $_url");
        _needReconnect = false;
        stream.add(ConnectionEvent(WebSocketType.reconnected));
        return;
      }
      debugger("WebSocket Connected: $_url");
      stream.add(ConnectionEvent(WebSocketType.connected));
      setSocketType(WebSocketType.connected);
    });
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
          if (_url == null) return;
          if (!_needReconnect) {
            debugger("WebSocket  Don`t have pong");

            _controller?.sink.close();
            disconnect();
          }

          _cancelTimer();
          _needReconnect = true;
          initialize(
            url: _url!,
            parameters: _parameters ?? <String, dynamic>{},
          );
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
    disconnect();

    _streamSubscription?.cancel();
    _streamSubscription = null;
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
    Map<String, dynamic>? parameters,
    bool enablePing = true,
  }) async {
    _parameters = parameters;
    bool success = await initialize(
      url: url,
      enablePing: enablePing,
      parameters: parameters,
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
    _timerOfConfirmationHasConnected?.cancel();
    closeSection();
    stream.close();
    super.dispose();
  }
}
