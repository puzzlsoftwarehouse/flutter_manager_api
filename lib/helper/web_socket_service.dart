import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:log_print/log_print.dart';
import 'package:manager_api/helper/web_socket_manager.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';
import 'package:manager_api/utils/timer_utils.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_client/web_socket_client.dart';

enum WebSocketType {
  connected(slug: "connected"),
  disconnected(slug: "disconnected"),
  disconnecting(slug: "disconnecting"),
  connecting(slug: "connecting"),
  reconnected(slug: "reconnected"),
  reconnecting(slug: "reconnecting");

  final String? slug;
  const WebSocketType({this.slug});

  bool get isConnected => this == WebSocketType.connected;
  bool get isDisconnected => this == WebSocketType.disconnected;
  bool get isDisconnecting => this == WebSocketType.disconnecting;
  bool get isConnecting => this == WebSocketType.connecting;
  bool get isReconnected => this == WebSocketType.reconnected;
  bool get isReconnecting => this == WebSocketType.reconnecting;
}

class WebSocketService extends WebSocketManager with ChangeNotifier {
  final TimerUtils _socketTimer = TimerUtils();
  Completer<bool> _completer = Completer<bool>();

  BehaviorSubject<ResultLR<WebSocketType, dynamic>>? _stream;
  @override
  BehaviorSubject<ResultLR<WebSocketType, dynamic>>? get stream => _stream;

  String? _id;
  @override
  String? get id => _id;

  String? _type;
  @override
  String? get type => _type;

  WebSocket? _controller;
  @override
  WebSocket? get controller => _controller;

  String? _url;

  WebSocketType _socketType = WebSocketType.connecting;
  @override
  WebSocketType get socketType => _socketType;

  WebSocketService({
    required String type,
    BehaviorSubject<ResultLR<WebSocketType, dynamic>>? stream,
    String? id,
  }) {
    _id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    _type = type;
    _stream = stream ?? BehaviorSubject<ResultLR<WebSocketType, dynamic>>();
  }

  @override
  Future<void> initialize({
    required String url,
    required String token,
  }) async {
    _completer = Completer<bool>();

    _socketTimer.updateWithTimer(() async {
      try {
        _url = url;

        await closeSection();
        setSocketType(WebSocketType.connecting);

        String beforeString = url.contains("?") ? "&" : "?";

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
              _stream?.add(Right(jsonEncode(result)));
            }
          } catch (_) {
            debugger("$event");
            _stream?.add(Right(event));
            setSocketType(WebSocketType.connected);
          }
        });
      } catch (e) {
        debugger("WebSocket Error: $e");
        setSocketType(WebSocketType.disconnected);
      }

      _completer.complete(true);
    }, duration: Duration(seconds: 1));

    await _completer.future;
    return;
  }

  @override
  void checkConnection(ConnectionState state) async {
    if (state is Connecting) {
      debugger("Connecting... $_url");
      setSocketType(WebSocketType.connecting);
    }

    if (state is Connected) {
      debugger("Connected... $_url");
      setSocketType(WebSocketType.connected);
    }

    if (state is Reconnecting) {
      debugger("Reconnecting... $_url");
      setSocketType(WebSocketType.reconnecting);
    }

    if (state is Reconnected) {
      debugger("Reconnected... $_url");
      setSocketType(WebSocketType.reconnected);
    }

    if (state is Disconnecting) {
      debugger("Disconnecting... $_url");
      setSocketType(WebSocketType.disconnecting);
    }

    if (state is Disconnected) {
      debugger("Disconnected... $_url");
      setSocketType(WebSocketType.disconnected);
    }
  }

  @override
  void sendMessage(String message) {
    _controller?.send(message);
  }

  @override
  Future<void> closeSection() async {
    setSocketType(WebSocketType.disconnected);

    _controller?.close();
    _controller = null;

    _stream?.close();
    _stream = BehaviorSubject<ResultLR<WebSocketType, dynamic>>();
  }

  @override
  void setSocketType(WebSocketType value) {
    _socketType = value;
    notifyListeners();

    _stream?.add(Left(value));
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
    closeSection();
    super.dispose();
  }
}
