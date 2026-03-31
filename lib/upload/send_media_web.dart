import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as web;

class SendMedia {
  SendMedia._();

  static Future<Map<String, dynamic>> sendMedia({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const <String, dynamic>{},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    final _WebSendMediaUploader uploader = _WebSendMediaUploader(
      file: file,
      url: url,
      parameters: parameters,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    );
    return uploader.start();
  }
}

class _WebSendMediaUploader {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  _WebSendMediaUploader({
    required this.file,
    required this.url,
    required this.parameters,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  late final Completer<Map<String, dynamic>> _resultCompleter =
      Completer<Map<String, dynamic>>();
  late final Uri _uploadUri = Uri.parse(url).replace(
    queryParameters: parameters.map(
      (String key, dynamic value) => MapEntry(key, value.toString()),
    ),
  );
  late final web.XMLHttpRequest _xmlHttpRequest = web.XMLHttpRequest();
  StreamSubscription<void>? _cancelSubscription;
  bool _isFinished = false;

  Future<Map<String, dynamic>> start() async {
    final web.Blob fileBlob = await _loadFileBlob();
    final web.FormData formData = web.FormData();
    formData.append('file', fileBlob, file.name);

    web.EventStreamProviders.progressEvent
        .forTarget(_xmlHttpRequest.upload)
        .listen((web.ProgressEvent progressEvent) {
          final int total = progressEvent.total;
          if (total <= 0) {
            return;
          }
          final int progress = ((progressEvent.loaded / total) * 100)
              .toInt()
              .clamp(0, 100);
          streamProgress?.add(progress);
        });

    _xmlHttpRequest.onLoad.first.then((_) {
      _finish(_parseLoadResult());
    });

    _xmlHttpRequest.onError.first.then((_) {
      _finish(
        _failureMap(
          code: 'noConnection',
          message:
              'The XMLHttpRequest onError callback was called. This usually indicates a network or CORS failure.',
        ),
      );
    });

    web.EventStreamProviders.abortEvent.forTarget(_xmlHttpRequest).first.then((_) {
      _finish(
        _failureMap(
          code: DefaultAPIFailures.cancelErrorCode,
          message: 'canceled by user',
        ),
      );
    });

    web.EventStreamProviders.timeoutEvent.forTarget(_xmlHttpRequest).first.then((_) {
      _finish(_failureMap(code: 'timeout', message: 'tempo excedido'));
    });

    _cancelSubscription = cancelToken?.whenCancel.asStream().listen((_) {
      if (_isFinished) {
        return;
      }
      _xmlHttpRequest.abort();
      _finish(
        _failureMap(
          code: DefaultAPIFailures.cancelErrorCode,
          message: 'canceled by user',
        ),
      );
    });

    _xmlHttpRequest.open('POST', _uploadUri.toString(), true);
    _xmlHttpRequest.timeout = const Duration(minutes: 30).inMilliseconds;
    _setHeaders();
    _xmlHttpRequest.send(formData);

    return _resultCompleter.future;
  }

  Future<web.Blob> _loadFileBlob() async {
    final String filePath = file.path;
    final bool canFetchBlobFromPath = _canFetchBlobFromPath(filePath);

    if (canFetchBlobFromPath) {
      try {
        final web.Response response = await web.window.fetch(filePath.toJS).toDart;
        if (response.ok) {
          return await response.blob().toDart;
        }
      } catch (_) {}
    }

    final Uint8List fileBytes = await file.readAsBytes();
    return _createBlobFromBytes(fileBytes, file.mimeType);
  }

  bool _canFetchBlobFromPath(String path) {
    if (path.isEmpty) {
      return false;
    }

    if (path.startsWith('blob:') ||
        path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/')) {
      return true;
    }

    return false;
  }

  web.Blob _createBlobFromBytes(Uint8List fileBytes, String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) {
      return web.Blob(<JSUint8Array>[fileBytes.toJS].toJS);
    }

    return web.Blob(
      <JSUint8Array>[fileBytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
  }

  void _setHeaders() {
    final Map<String, String> requestHeaders = headers ?? <String, String>{};
    for (final MapEntry<String, String> header in requestHeaders.entries) {
      final String headerName = header.key.toLowerCase();
      if (headerName == 'content-type') {
        continue;
      }
      _xmlHttpRequest.setRequestHeader(header.key, header.value);
    }
  }

  Map<String, dynamic> _parseLoadResult() {
    final int status = _xmlHttpRequest.status;
    final String responseText = _xmlHttpRequest.responseText;

    if (status >= 200 && status < 300) {
      final Object? decodedResponse = _tryDecodeJson(responseText);
      if (decodedResponse is Map<Object?, Object?>) {
        return <String, dynamic>{
          'data': Map<String, dynamic>.from(decodedResponse),
        };
      }

      return _failureMap(code: '000', message: 'Invalid upload response');
    }

    final Object? decodedError = _tryDecodeJson(responseText);
    if (decodedError is Map<Object?, Object?>) {
      final Map<String, dynamic> errorMap = Map<String, dynamic>.from(decodedError);
      return _failureMap(
        code: errorMap['exception_code']?.toString() ?? status.toString(),
        message:
            errorMap['detail']?.toString() ??
            errorMap['message']?.toString() ??
            _friendlyUploadFailureMessage(
              statusCode: status,
              fallbackMessage: _xmlHttpRequest.statusText,
            ),
      );
    }

    return _failureMap(
      code: status.toString(),
      message: _friendlyUploadFailureMessage(
        statusCode: status,
        fallbackMessage: responseText.isNotEmpty
            ? responseText
            : _xmlHttpRequest.statusText,
      ),
    );
  }

  String _friendlyUploadFailureMessage({
    required int statusCode,
    required String fallbackMessage,
  }) {
    if (statusCode == 413) {
      return 'This file is larger than the server upload limit.';
    }
    return fallbackMessage;
  }

  Object? _tryDecodeJson(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _failureMap({
    required String code,
    required String message,
  }) {
    return <String, dynamic>{
      'exception_code': code,
      'detail': message,
    };
  }

  void _finish(Map<String, dynamic> result) {
    if (_isFinished) {
      return;
    }
    _isFinished = true;
    _cancelSubscription?.cancel();
    _cancelSubscription = null;
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(result);
    }
  }
}
