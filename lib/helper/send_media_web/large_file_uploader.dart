import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// Callback exposing currently upload progress.
typedef UploadProgressListener = Function(int progress);

/// Callback exposing upload fail event.
typedef UploadFailureListener = Function();

/// Callback exposing upload complete event.
typedef UploadCompleteListener = Function(String response);

/// Callback exposing one or multiple files selected.
typedef OnFileSelectedListener = Function(html.File file);

/// Uploading large file util by using JS in flutter web.
class LargeFileUploader {
  String requestId = UniqueKey().toString();
  html.Worker? _worker;
  LargeFileUploader() {
    _worker = html.Worker('upload_worker.js');
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
    _worker?.postMessage({
      'method': method,
      'uploadUrl': uploadUrl,
      'data': data,
      'headers': headers,
      'requestId': requestId,
    });
    _worker?.onError.listen((event) {
      log("Request abort or is necessary to add file upload_worker.js inside project on folder 'web' like 'web/upload_worker.js");
    });

    _worker?.onMessage.listen((data) {
      _handleCallbacks(
        data.data,
        onSendProgress: onSendProgress,
        onFailure: onFailure,
        onComplete: onComplete,
      );
    });
  }

  void onCancel() {
    _worker?.postMessage({
      'method': 'abort',
      'requestId': requestId,
    });
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
      case FileTypes.image:
        return 'image/*';
      case FileTypes.imagePng:
        return 'image/png';
      case FileTypes.imageGif:
        return 'image/gif';
      case FileTypes.imageJpeg:
        return 'image/jpeg';
      case FileTypes.audio:
        return 'audio/*';
      case FileTypes.video:
        return 'video/*';
    }
  }
}
