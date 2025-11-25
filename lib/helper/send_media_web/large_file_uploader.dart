import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'upload_worker_code.dart';

typedef UploadProgressListener = void Function(int progress);
typedef UploadFailureListener = void Function(String? error);
typedef UploadCompleteListener = void Function(String response);
typedef OnFileSelectedListener = void Function(web.File file);
typedef CancelCallback = void Function(void Function() onCancel);

class LargeFileUploader {
  String requestId = UniqueKey().toString();
  web.Worker? _worker;

  LargeFileUploader() {
    try {
      requestId = UniqueKey().toString();
    } catch (e) {
      requestId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final String workerCode = uploadWorkerCode;
    final JSArray<JSAny> blobParts = [workerCode.toJS].toJS;
    final web.BlobPropertyBag blobOptions =
        web.BlobPropertyBag(type: 'application/javascript');
    final web.Blob blob = web.Blob(blobParts, blobOptions);
    final String blobUrl = web.URL.createObjectURL(blob);
    _worker = web.Worker(blobUrl.toJS);
  }

  void upload({
    required String uploadUrl,
    required UploadProgressListener onSendProgress,
    required Map<String, dynamic> data,
    String method = 'POST',
    Map<String, String>? headers,
    UploadFailureListener? onFailure,
    UploadCompleteListener? onComplete,
    CancelCallback? cancelFunction,
  }) {
    if (_worker == null) {
      onFailure?.call("Web Worker is not supported in this environment.");
      return;
    }

    if (cancelFunction != null) {
      cancelFunction(onCancel);
    }

    final Map<String, Object?> message = <String, Object?>{
      'method': method,
      'uploadUrl': uploadUrl,
      'data': data,
      'headers': headers,
      'requestId': requestId,
    };

    _worker?.postMessage(message.jsify());

    _worker?.addEventListener(
        'error',
        (web.Event event) {
          onFailure?.call("");
        }.toJS);

    _worker?.addEventListener(
        'message',
        (web.MessageEvent event) {
          final messageData = event.data;

          if (messageData != null) {
            try {
              final dartData = messageData.dartify();
              _handleCallbacks(
                dartData,
                onSendProgress: onSendProgress,
                onFailure: onFailure,
                onComplete: onComplete,
              );
            } catch (e) {
              onFailure?.call(e.toString());
            }
          }
        }.toJS);
  }

  void onCancel() {
    final Map<String, Object?> message = <String, Object?>{
      'method': 'abort',
      'requestId': requestId,
    };
    _worker?.postMessage(message.jsify());
  }

  void _handleCallbacks(
    dynamic data, {
    required UploadProgressListener onSendProgress,
    UploadFailureListener? onFailure,
    UploadCompleteListener? onComplete,
  }) {
    if (data == null) return;

    if (data is num) {
      onSendProgress(data.toInt());
      return;
    }

    final String dataString = data.toString();

    if (dataString == 'request failed') {
      onFailure?.call("Request failed");
      return;
    }

    if (data is String) {
      onComplete?.call(data);
      return;
    }

    if (data is Map<dynamic, dynamic>) {
      final Object? errorValue = data['error'];
      if (errorValue != null && errorValue is String) {
        onFailure?.call(errorValue);
        return;
      }
    }

    try {
      final String jsonString = data.toString();
      onComplete?.call(jsonString);
    } catch (e) {
      onComplete?.call(dataString);
    }
  }
}
