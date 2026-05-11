import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_print/log_print.dart';
import 'package:manager_api/models/websocket/web_socket_type.dart';
import 'package:manager_api/websocket/web_socket_constants.dart';
import 'package:manager_api/websocket/web_socket_incoming.dart';
import 'package:manager_api/websocket/web_socket_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService extends WebSocketManager with ChangeNotifier {
  String? _id;
  String? _type;

  String? _url;
  Map<String, dynamic>? _parameters;
  WebSocketChannel? _controller;
  StreamSubscription<dynamic>? _streamSubscription;
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

  int _connectionSerial = 0;
  int? _boundConnectionSerial;

  final Random _random = Random();

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
    Subject<SocketEvent>? stream,
  }) {
    _id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    _type = type;
    super.stream = stream ?? PublishSubject<SocketEvent>();
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

    if (_isClosed) {
      return false;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;

    final int connectionSerial = ++_connectionSerial;
    _boundConnectionSerial = null;

    setSocketType(WebSocketType.connecting);

    try {
      _disposeChannelAndSubscription();

      final Uri uri = _buildUri(url, parameters);
      final WebSocketChannel channel = WebSocketChannel.connect(uri);

      _controller = channel;
      _boundConnectionSerial = connectionSerial;

      checkConnection();

      _streamSubscription = channel.stream.listen(
        _onStreamEventForSession(connectionSerial),
        onDone: () => _onStreamDone(connectionSerial),
        onError: (Object error, StackTrace _) =>
            _onStreamError(error, connectionSerial),
      );
    } catch (error) {
      debugger("WebSocket Error: $error");
      _boundConnectionSerial = null;
      disconnect();
      _scheduleReconnect();

      return false;
    }

    _emitConnecting();
    _startConnectionConfirmation();

    return _controller != null;
  }

  Uri _buildUri(String url, Map<String, dynamic>? parameters) {
    Uri uri = Uri.parse(url);
    final Map<String, dynamic> queryParameters = <String, dynamic>{
      ...uri.queryParameters,
      ...?parameters,
    };

    return uri.replace(
      queryParameters: queryParameters.map(
        (String key, dynamic value) => MapEntry<String, String>(
          key,
          value?.toString() ?? '',
        ),
      ),
    );
  }

  void Function(dynamic event) _onStreamEventForSession(int session) {
    return (dynamic event) => _onStreamEvent(event, session);
  }

  void _onStreamEvent(dynamic event, int session) {
    if (session != _boundConnectionSerial) {
      return;
    }

    if (event is! String) {
      debugger(event.toString());
      stream.add(MessageEvent(event));

      if (_socketType != WebSocketType.connected) {
        setSocketType(WebSocketType.connected);
      }

      return;
    }

    if (webSocketIncomingIsPong(event)) {
      _receivedPong = true;

      if (_awaitingConnectionConfirmation) {
        _onConnectionConfirmedByPong();
      }

      return;
    }

    debugger(event.toString());
    stream.add(MessageEvent(event));

    if (_socketType != WebSocketType.connected) {
      setSocketType(WebSocketType.connected);
    }
  }

  void _onStreamDone(int session) {
    if (session != _boundConnectionSerial) {
      return;
    }

    disconnect();
    _scheduleReconnect();
  }

  void _onStreamError(Object error, int session) {
    if (session != _boundConnectionSerial) {
      return;
    }

    debugger("WebSocket Stream Error: $error");
    disconnect();
    _scheduleReconnect();
  }

  void disconnect() {
    debugger("WebSocket Disconnected $_url");
    stream.add(ConnectionEvent(WebSocketType.disconnected));
    setSocketType(WebSocketType.disconnected);

    _boundConnectionSerial = null;

    _connectionConfirmationDelayTimer?.cancel();
    _connectionConfirmationDelayTimer = null;
    _connectionConfirmationTimeoutTimer?.cancel();
    _connectionConfirmationTimeoutTimer = null;
    _awaitingConnectionConfirmation = false;

    _cancelPingTimer();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    final WebSocketChannel? channel = _controller;
    _controller = null;
    channel?.sink.close();
  }

  void _disposeChannelAndSubscription() {
    _connectionConfirmationDelayTimer?.cancel();
    _connectionConfirmationDelayTimer = null;
    _connectionConfirmationTimeoutTimer?.cancel();
    _connectionConfirmationTimeoutTimer = null;
    _awaitingConnectionConfirmation = false;

    _cancelPingTimer();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    final WebSocketChannel? channel = _controller;
    _controller = null;
    channel?.sink.close();
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
          Timer(WebSocketConstants.connectionConfirmationDelay, () {
        if (_controller == null || _isClosed) {
          return;
        }

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

    _connectionConfirmationDelayTimer =
        Timer(WebSocketConstants.connectionConfirmationDelay, () {
      if (_controller == null || _isClosed) {
        return;
      }

      _awaitingConnectionConfirmation = true;
      _receivedPong = false;
      _controller!.sink.add(WebSocketConstants.pingPayloadJson);

      _connectionConfirmationTimeoutTimer?.cancel();
      _connectionConfirmationTimeoutTimer = Timer(
        WebSocketConstants.connectionConfirmationTimeout,
        _onConnectionConfirmationTimeout,
      );
    });
  }

  void _onConnectionConfirmationTimeout() {
    if (!_awaitingConnectionConfirmation || _isClosed) {
      return;
    }

    debugger("WebSocket connection confirmation timeout (no pong): $_url");
    _awaitingConnectionConfirmation = false;
    _controller?.sink.close();
    disconnect();
    _scheduleReconnect();
  }

  void _onConnectionConfirmedByPong() {
    if (!_awaitingConnectionConfirmation || _isClosed) {
      return;
    }

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
    if (!enablePing) {
      return;
    }

    if (_controller == null || _isClosed) {
      return;
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(WebSocketConstants.pingInterval, (_) {
      if (_controller == null || !enablePing) {
        _cancelPingTimer();

        return;
      }

      _controller!.sink.add(WebSocketConstants.pingPayloadJson);
      _receivedPong = false;

      _pongCheckTimer?.cancel();
      _pongCheckTimer = Timer(WebSocketConstants.pongWait, () {
        _pongCheckTimer = null;

        if (_isClosed) {
          return;
        }

        if (!_receivedPong) {
          if (_url == null) {
            return;
          }

          debugger("WebSocket Don't have pong");
          _controller?.sink.close();
          disconnect();
          _scheduleReconnect();
        }
      });
    });
  }

  void _scheduleReconnect() {
    if (_isClosed || _isReconnecting || _url == null) {
      return;
    }

    _isReconnecting = true;
    _needReconnect = true;

    final int exponent = _reconnectAttemptCount
        .clamp(0, WebSocketConstants.reconnectBackoffClamp);
    final Duration baseDelay =
        WebSocketConstants.reconnectBaseDelay * (1 << exponent);
    final Duration cappedDelay = baseDelay > WebSocketConstants.reconnectMaxDelay
        ? WebSocketConstants.reconnectMaxDelay
        : baseDelay;

    final int jitterMilliseconds = (cappedDelay.inMilliseconds *
            WebSocketConstants.reconnectJitterFactor *
            _random.nextDouble())
        .round();
    final Duration delayWithJitter =
        cappedDelay + Duration(milliseconds: jitterMilliseconds);

    _reconnectAttemptCount++;

    debugger(
        "WebSocket scheduling reconnect attempt $_reconnectAttemptCount in ${delayWithJitter.inMilliseconds}ms: $_url");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delayWithJitter, () {
      _isReconnecting = false;

      if (_isClosed || _url == null) {
        return;
      }

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
    if (_controller == null || _isClosed) {
      return;
    }

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
    if (_socketType == value) {
      return;
    }

    _socketType = value;
    notifyListeners();
  }

  @override
  void debugger(String name) {
    if (!WebSocketConstants.loggerEnabled) {
      return;
    }

    if (kReleaseMode) {
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      debugPrint("WebSocket $_type: $name");

      return;
    }

    LogPrint(
      name,
      type: LogPrintType.custom,
      title: "WebSocket $_type",
      titleBackgroundColor: Colors.lightBlue.shade700,
      messageColor: Colors.lightBlueAccent.shade100,
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
