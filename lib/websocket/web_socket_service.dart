import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_print/log_print.dart';
import 'package:manager_api/models/websocket/web_socket_type.dart';
import 'package:manager_api/websocket/web_socket_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService extends WebSocketManager with ChangeNotifier {
  static const Duration _connectionConfirmationDelay = Duration(seconds: 1);
  static const Duration _connectionConfirmationTimeoutDuration =
      Duration(seconds: 5);
  static const Duration _reconnectBaseDelay = Duration(seconds: 1);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);

  String? _id;
  String? _type;

  String? _url;
  Map<String, dynamic>? _parameters;
  WebSocketChannel? _controller;
  StreamSubscription? _streamSubscription;
  WebSocketType _socketType = WebSocketType.connecting;
  bool _isClosed = false;
  bool enablePing = true;

  bool _receivedPong = false;
  bool _awaitingConnectionConfirmation = false;
  bool _isReconnectAttempt = false;

  Timer? _pingTimer;
  Timer? _pongCheckTimer;
  Timer? _connectionConfirmationDelayTimer;
  Timer? _connectionConfirmationTimeoutTimer;

  bool _needReconnect = false;
  bool _isReconnecting = false;
  int _reconnectAttemptCount = 0;
  Timer? _reconnectTimer;

  @override
  String? get id => _id;

  @override
  String? get type => _type;

  @override
  WebSocketChannel? get controller => _controller;

  @override
  WebSocketType get socketType => _socketType;

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
  Future<bool> create({
    required String url,
    Map<String, dynamic>? parameters,
    bool enablePing = true,
  }) async {
    _parameters = parameters;
    return initialize(url: url, enablePing: enablePing, parameters: parameters);
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
        ...?parameters,
      };
      uri = uri.replace(queryParameters: queryParameters);
      _controller = WebSocketChannel.connect(uri);

      checkConnection();

      _streamSubscription = _controller!.stream.listen(
        _onStreamEvent,
        onDone: _onStreamDone,
        onError: _onStreamError,
      );
    } catch (error) {
      debugger("WebSocket Error: $error");
      disconnect();
      _scheduleReconnect();
      return false;
    }

    _emitConnecting();
    _startConnectionConfirmation();
    return _controller != null;
  }

  void _onStreamEvent(dynamic event) {
    try {
      final dynamic decoded = jsonDecode(event as String);
      if (decoded is Map && decoded['type'] == "pong") {
        _receivedPong = true;
        if (_awaitingConnectionConfirmation) {
          _onConnectionConfirmedByPong();
        }
        return;
      }
    } catch (_) {}
    debugger(event.toString());
    stream.add(MessageEvent(event));
    setSocketType(WebSocketType.connected);
  }

  void _onStreamDone() {
    disconnect();
    _scheduleReconnect();
  }

  void _onStreamError(Object error) {
    debugger("WebSocket Stream Error: $error");
    disconnect();
    _scheduleReconnect();
  }

  void disconnect() {
    debugger("WebSocket Disconnected $_url");
    stream.add(ConnectionEvent(WebSocketType.disconnected));
    setSocketType(WebSocketType.disconnected);

    _connectionConfirmationDelayTimer?.cancel();
    _connectionConfirmationDelayTimer = null;
    _connectionConfirmationTimeoutTimer?.cancel();
    _connectionConfirmationTimeoutTimer = null;
    _awaitingConnectionConfirmation = false;

    _cancelPingTimer();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _controller?.sink.close();
    _controller = null;
  }

  void _emitConnecting() {
    debugger("WebSocket Connecting: $_url");
    stream.add(ConnectionEvent(WebSocketType.connecting));
    setSocketType(WebSocketType.connecting);
  }

  void _startConnectionConfirmation() {
    _connectionConfirmationDelayTimer?.cancel();
    _connectionConfirmationTimeoutTimer?.cancel();
    _awaitingConnectionConfirmation = false;
    _isReconnectAttempt = _needReconnect;

    if (!enablePing) {
      _connectionConfirmationDelayTimer =
          Timer(_connectionConfirmationDelay, () {
        if (_controller == null || _isClosed) return;
        _resetReconnectState();
        if (_isReconnectAttempt) {
          debugger("WebSocket Reconnected: $_url");
          stream.add(ConnectionEvent(WebSocketType.reconnected));
        } else {
          debugger("WebSocket Connected: $_url");
          stream.add(ConnectionEvent(WebSocketType.connected));
        }
        setSocketType(WebSocketType.connected);
      });
      return;
    }

    _connectionConfirmationDelayTimer = Timer(_connectionConfirmationDelay, () {
      if (_controller == null || _isClosed) return;
      _awaitingConnectionConfirmation = true;
      _receivedPong = false;
      _controller!.sink.add(jsonEncode({"type": "ping"}));

      _connectionConfirmationTimeoutTimer?.cancel();
      _connectionConfirmationTimeoutTimer = Timer(
        _connectionConfirmationTimeoutDuration,
        _onConnectionConfirmationTimeout,
      );
    });
  }

  void _onConnectionConfirmationTimeout() {
    if (!_awaitingConnectionConfirmation || _isClosed) return;
    debugger("WebSocket connection confirmation timeout (no pong): $_url");
    _awaitingConnectionConfirmation = false;
    _controller?.sink.close();
    disconnect();
    _scheduleReconnect();
  }

  void _onConnectionConfirmedByPong() {
    if (!_awaitingConnectionConfirmation || _isClosed) return;
    _connectionConfirmationTimeoutTimer?.cancel();
    _connectionConfirmationTimeoutTimer = null;
    _awaitingConnectionConfirmation = false;
    _resetReconnectState();

    if (_isReconnectAttempt) {
      debugger("WebSocket Reconnected (confirmed by pong): $_url");
      stream.add(ConnectionEvent(WebSocketType.reconnected));
    } else {
      debugger("WebSocket Connected (confirmed by pong): $_url");
      stream.add(ConnectionEvent(WebSocketType.connected));
    }
    setSocketType(WebSocketType.connected);
  }

  @override
  void checkConnection() {
    if (!enablePing) return;
    if (_controller == null || _isClosed) return;

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_controller == null || !enablePing) {
        _cancelPingTimer();
        return;
      }

      _controller!.sink.add(jsonEncode({"type": "ping"}));
      _receivedPong = false;

      _pongCheckTimer?.cancel();
      _pongCheckTimer = Timer(const Duration(seconds: 5), () {
        _pongCheckTimer = null;
        if (_isClosed) return;
        if (!_receivedPong) {
          if (_url == null) return;
          debugger("WebSocket Don't have pong");
          _controller?.sink.close();
          disconnect();
          _scheduleReconnect();
        }
      });
    });
  }

  void _scheduleReconnect() {
    if (_isClosed || _isReconnecting || _url == null) return;

    _isReconnecting = true;
    _needReconnect = true;

    final int exponent = _reconnectAttemptCount.clamp(0, 5);
    final Duration baseDelay = _reconnectBaseDelay * (1 << exponent);
    final Duration cappedDelay =
        baseDelay > _reconnectMaxDelay ? _reconnectMaxDelay : baseDelay;

    final int jitterMilliseconds =
        (cappedDelay.inMilliseconds * 0.3 * Random().nextDouble()).round();
    final Duration delayWithJitter =
        cappedDelay + Duration(milliseconds: jitterMilliseconds);

    _reconnectAttemptCount++;

    debugger(
        "WebSocket scheduling reconnect attempt $_reconnectAttemptCount in ${delayWithJitter.inMilliseconds}ms: $_url");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delayWithJitter, () {
      _isReconnecting = false;
      if (_isClosed || _url == null) return;
      initialize(url: _url!, parameters: _parameters);
    });
  }

  void _resetReconnectState() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttemptCount = 0;
    _isReconnecting = false;
    _needReconnect = false;
  }

  void _cancelPingTimer() {
    _pongCheckTimer?.cancel();
    _pongCheckTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  @override
  void sendMessage(String message) {
    if (_controller == null || _isClosed) return;
    _controller!.sink.add(message);
  }

  @override
  void closeSection() {
    _isClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    disconnect();
  }

  @override
  void setSocketType(WebSocketType value) {
    if (_socketType == value) return;
    _socketType = value;
    notifyListeners();
  }

  @override
  void debugger(String name) {
    if (kReleaseMode) return;

    final bool isLoggingEnabled = const bool.fromEnvironment(
      "WEBSOCKETLOGGER",
      defaultValue: true,
    );
    if (!isLoggingEnabled) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      debugPrint("WebSocket $_type: $name");
      return;
    }

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
    _cancelPingTimer();
    _reconnectTimer?.cancel();
    _connectionConfirmationDelayTimer?.cancel();
    _connectionConfirmationTimeoutTimer?.cancel();
    closeSection();
    stream.close();
    super.dispose();
  }
}
