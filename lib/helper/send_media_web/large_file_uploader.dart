import 'package:flutter/foundation.dart';
import 'package:web/web.dart';
import 'dart:js_interop';

typedef UploadProgressListener = Function(int progress);
typedef UploadFailureListener = Function();
typedef UploadCompleteListener = Function(String response);
typedef OnFileSelectedListener = Function(File file);

class LargeFileUploader {
  String requestId = UniqueKey().toString();
  Worker? _worker;

  LargeFileUploader() {
    JSString str = 'upload_worker.js'.toJS;
    _worker = Worker(str);
  }

  void upload({
    required String uploadUrl,
    required UploadProgressListener onSendProgress,
    required Map<String, dynamic> data,
    String method = 'POST',
    Map<String, dynamic>? headers,
    UploadFailureListener? onFailure,
    UploadCompleteListener? onComplete,
    Function(Function() onCancel)? cancelFunction,
  }) {
    if (cancelFunction != null) {
      cancelFunction(onCancel);
    }

    Map<String, dynamic> str = {
      'method': method,
      'uploadUrl': uploadUrl,
      'data': data,
      'headers': headers,
      'requestId': requestId,
    };

    JSBoxedDartObject jsStr = str.toJSBox;
    _worker?.postMessage(jsStr);

    _worker?.addEventListener(
      "error",
      (event) {
        console.log("Received message from worker: ${event.data}".toJS);
      }.toJS,
    );

    _worker?.addEventListener(
      "message",
      (data) {
        _handleCallbacks(
          data.data,
          onSendProgress: onSendProgress,
          onFailure: onFailure,
          onComplete: onComplete,
        );
      }.toJS,
    );
  }

  void onCancel() {
    Map<String, dynamic> str = {
      'method': 'abort',
      'requestId': requestId,
    };

    JSBoxedDartObject jsStr = str.toJSBox;
    _worker?.postMessage(jsStr);
  }

  void _handleCallbacks(
    data, {
    required UploadProgressListener onSendProgress,
    UploadFailureListener? onFailure,
    UploadCompleteListener? onComplete,
  }) {
    if (data == null) return;

    if (data is int) {
      onSendProgress.call(data);
      return;
    }
    if (data.toString() == 'request failed') {
      onFailure?.call();
      return;
    }
    onComplete?.call(data);
  }
}

enum FileTypes {
  file,
  image,
  imagePng,
  imageGif,
  imageJpeg,
  audio,
  video,
}

extension FileTypesExtention on FileTypes {
  String get value {
    switch (this) {
      case FileTypes.file:
        return '';
      case FileTypes.imagePng:
        return 'image/png';
      case FileTypes.imageGif:
        return 'image/gif';
      case FileTypes.imageJpeg:
        return 'image/jpeg';
      case FileTypes.image:
        return 'image/*';
      case FileTypes.audio:
        return 'audio/*';
      case FileTypes.video:
        return 'video/*';
    }
  }
}
