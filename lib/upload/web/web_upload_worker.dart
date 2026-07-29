import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'upload_worker_code.dart';

typedef WebUploadProgressListener = void Function(int progress);
typedef WebUploadBytesListener = void Function(int loaded, int total);

class WebUploadWorker {
  WebUploadWorker() {
    _createWorker();
    _worker?.addEventListener(
      'message',
      ((web.MessageEvent event) => _handleWorkerMessage(event)).toJS,
    );
    _worker?.addEventListener(
      'error',
      ((web.Event _) {
        final List<_PendingWebUpload> pending =
            List<_PendingWebUpload>.from(_pending.values);
        for (final _PendingWebUpload item in pending) {
          item.finish(
            _failureMap(
              code: 'noConnection',
              message: 'Failed to run upload worker',
            ),
          );
        }
      }).toJS,
    );
  }

  web.Worker? _worker;
  String? _workerBlobUrl;
  bool _isDisposed = false;
  int _requestSequence = 0;
  final Map<String, _PendingWebUpload> _pending = <String, _PendingWebUpload>{};

  Future<Map<String, dynamic>> upload({
    required String uploadUrl,
    required web.Blob fileBlob,
    required String fileName,
    Map<String, String>? headers,
    WebUploadProgressListener? onProgress,
    void Function(void Function() cancelUpload)? registerCancel,
  }) async {
    return _enqueue(
      message: <String, Object?>{
        'method': 'POST',
        'mode': 'form',
        'uploadUrl': uploadUrl,
        'headers': headers,
        'data': <String, Object?>{
          'file': <String, Object?>{
            'blob': fileBlob,
            'name': fileName,
          },
        },
      },
      onProgress: onProgress,
      registerCancel: registerCancel,
    );
  }

  Future<Map<String, dynamic>> putRaw({
    required String uploadUrl,
    required web.Blob blob,
    Map<String, String>? headers,
    WebUploadBytesListener? onBytes,
    void Function(void Function() cancelUpload)? registerCancel,
  }) async {
    return _enqueue(
      message: <String, Object?>{
        'method': 'PUT',
        'mode': 'raw_put',
        'uploadUrl': uploadUrl,
        'headers': headers,
        'data': <String, Object?>{
          'blob': blob,
        },
      },
      onBytes: onBytes,
      registerCancel: registerCancel,
    );
  }

  Future<Map<String, dynamic>> _enqueue({
    required Map<String, Object?> message,
    WebUploadProgressListener? onProgress,
    WebUploadBytesListener? onBytes,
    void Function(void Function() cancelUpload)? registerCancel,
  }) async {
    if (_worker == null) {
      return _failureMap(
        code: '000',
        message: 'Web Worker is not supported in this environment',
      );
    }

    final String requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${_requestSequence++}';
    final Completer<Map<String, dynamic>> resultCompleter =
        Completer<Map<String, dynamic>>();
    final _PendingWebUpload pending = _PendingWebUpload(
      requestId: requestId,
      resultCompleter: resultCompleter,
      onProgress: onProgress,
      onBytes: onBytes,
    );
    _pending[requestId] = pending;

    void cancelUpload() {
      if (pending.isFinished) {
        return;
      }
      _postMessage(<String, Object?>{
        'method': 'abort',
        'requestId': requestId,
      });
    }

    registerCancel?.call(cancelUpload);

    _postMessage(<String, Object?>{
      ...message,
      'requestId': requestId,
    });

    return resultCompleter.future;
  }

  void abortAll() {
    final List<_PendingWebUpload> pending =
        List<_PendingWebUpload>.from(_pending.values);
    for (final _PendingWebUpload item in pending) {
      _postMessage(<String, Object?>{
        'method': 'abort',
        'requestId': item.requestId,
      });
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    abortAll();
    final List<_PendingWebUpload> pending =
        List<_PendingWebUpload>.from(_pending.values);
    _pending.clear();
    for (final _PendingWebUpload item in pending) {
      item.finish(
        _failureMap(
          code: 'cancel',
          message: 'Request canceled',
        ),
      );
    }
    _worker?.terminate();
    _worker = null;
    if (_workerBlobUrl != null) {
      web.URL.revokeObjectURL(_workerBlobUrl!);
      _workerBlobUrl = null;
    }
  }

  void _handleWorkerMessage(web.MessageEvent event) {
    final Map<String, dynamic>? payload = _decodeWorkerPayload(event.data);
    if (payload == null) {
      return;
    }

    final String? kind = payload['kind']?.toString();
    final String? messageRequestId = payload['requestId']?.toString();
    if (messageRequestId == null) {
      return;
    }

    final _PendingWebUpload? pending = _pending[messageRequestId];
    if (pending == null) {
      return;
    }

    if (kind == 'progress') {
      final Object? progressValue = payload['value'];
      if (progressValue is num) {
        pending.onProgress?.call(progressValue.toInt().clamp(0, 100));
      }
      final Object? loaded = payload['loaded'];
      final Object? total = payload['total'];
      if (loaded is num && total is num) {
        pending.onBytes?.call(loaded.toInt(), total.toInt());
      }
      return;
    }

    if (kind == 'complete') {
      final Object? data = payload['data'];
      if (data is Map<Object?, Object?>) {
        pending.finish(<String, dynamic>{
          'data': Map<String, dynamic>.from(data),
        });
        _pending.remove(messageRequestId);
        return;
      }
      pending.finish(
        _failureMap(
          code: '000',
          message: 'Invalid upload response',
        ),
      );
      _pending.remove(messageRequestId);
      return;
    }

    if (kind == 'failure') {
      pending.finish(
        _failureMap(
          code: payload['exception_code']?.toString() ?? '000',
          message: payload['detail']?.toString() ?? 'Upload failed',
        ),
      );
      _pending.remove(messageRequestId);
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

class _PendingWebUpload {
  final String requestId;
  final Completer<Map<String, dynamic>> resultCompleter;
  final WebUploadProgressListener? onProgress;
  final WebUploadBytesListener? onBytes;
  bool isFinished = false;

  _PendingWebUpload({
    required this.requestId,
    required this.resultCompleter,
    required this.onProgress,
    required this.onBytes,
  });

  void finish(Map<String, dynamic> result) {
    if (isFinished) {
      return;
    }
    isFinished = true;
    if (!resultCompleter.isCompleted) {
      resultCompleter.complete(result);
    }
  }
}
