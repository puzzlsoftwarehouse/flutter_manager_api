import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'upload_worker_code.dart';

typedef WebUploadProgressListener = void Function(int progress);

class WebUploadWorker {
  WebUploadWorker() {
    _requestId = DateTime.now().microsecondsSinceEpoch.toString();
    _createWorker();
  }

  late final String _requestId;
  web.Worker? _worker;
  String? _workerBlobUrl;
  bool _isDisposed = false;

  Future<Map<String, dynamic>> upload({
    required String uploadUrl,
    required web.Blob fileBlob,
    required String fileName,
    Map<String, String>? headers,
    WebUploadProgressListener? onProgress,
    void Function(void Function() cancelUpload)? registerCancel,
  }) async {
    if (_worker == null) {
      return _failureMap(
        code: '000',
        message: 'Web Worker não suportado neste ambiente.',
      );
    }

    final Completer<Map<String, dynamic>> resultCompleter =
        Completer<Map<String, dynamic>>();
    var isFinished = false;

    void finish(Map<String, dynamic> result) {
      if (isFinished) {
        return;
      }
      isFinished = true;
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(result);
      }
    }

    void cancelUpload() {
      if (isFinished) {
        return;
      }
      _postMessage(<String, Object?>{
        'method': 'abort',
        'requestId': _requestId,
      });
    }

    void handleWorkerMessage(web.MessageEvent event) {
      final Map<String, dynamic>? payload = _decodeWorkerPayload(event.data);
      if (payload == null) {
        return;
      }

      final String? kind = payload['kind']?.toString();
      final String? messageRequestId = payload['requestId']?.toString();
      if (messageRequestId != null && messageRequestId != _requestId) {
        return;
      }

      if (kind == 'progress') {
        final Object? progressValue = payload['value'];
        if (progressValue is num) {
          onProgress?.call(progressValue.toInt().clamp(0, 100));
        }
        return;
      }

      if (kind == 'complete') {
        final Object? data = payload['data'];
        if (data is Map<Object?, Object?>) {
          finish(<String, dynamic>{
            'data': Map<String, dynamic>.from(data),
          });
          return;
        }
        finish(_failureMap(code: '000', message: 'Invalid upload response'));
        return;
      }

      if (kind == 'failure') {
        finish(
          _failureMap(
            code: payload['exception_code']?.toString() ?? '000',
            message: payload['detail']?.toString() ?? 'Request failed',
          ),
        );
      }
    }

    _worker?.addEventListener(
      'message',
      ((web.MessageEvent event) => handleWorkerMessage(event)).toJS,
    );

    _worker?.addEventListener(
      'error',
      ((web.Event _) {
        finish(
          _failureMap(
            code: 'noConnection',
            message: 'Falha ao executar o worker de upload.',
          ),
        );
      }).toJS,
    );

    registerCancel?.call(cancelUpload);

    _postMessage(<String, Object?>{
      'method': 'POST',
      'uploadUrl': uploadUrl,
      'requestId': _requestId,
      'headers': headers,
      'data': <String, Object?>{
        'file': <String, Object?>{
          'blob': fileBlob,
          'name': fileName,
        },
      },
    });

    return resultCompleter.future;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _worker?.terminate();
    _worker = null;
    if (_workerBlobUrl != null) {
      web.URL.revokeObjectURL(_workerBlobUrl!);
      _workerBlobUrl = null;
    }
  }

  void _createWorker() {
    final JSArray<JSAny> blobParts = <JSAny>[uploadWorkerCode.toJS].toJS;
    final web.Blob workerBlob = web.Blob(
      blobParts,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    _workerBlobUrl = web.URL.createObjectURL(workerBlob);
    _worker = web.Worker(_workerBlobUrl!.toJS);
  }

  void _postMessage(Map<String, Object?> message) {
    _worker?.postMessage(message.jsify());
  }

  Map<String, dynamic>? _decodeWorkerPayload(JSAny? rawPayload) {
    if (rawPayload == null) {
      return null;
    }

    final Object? dartPayload = rawPayload.dartify();
    if (dartPayload is Map<Object?, Object?>) {
      return Map<String, dynamic>.from(dartPayload);
    }

    if (dartPayload is String) {
      try {
        final Object? decoded = jsonDecode(dartPayload);
        if (decoded is Map<Object?, Object?>) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }

    return null;
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
}
