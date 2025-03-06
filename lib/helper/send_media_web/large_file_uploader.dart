import 'package:flutter/foundation.dart';
import '../../non_web.dart' if (dart.library.html) 'package:web/web.dart'
    as web;
import '../../non_web.dart' if (dart.library.html) 'dart:js_interop'
    as js_interop;

typedef UploadProgressListener = Function(int progress);
typedef UploadFailureListener = Function();
typedef UploadCompleteListener = Function(String response);
typedef OnFileSelectedListener = Function(web.File file);

class LargeFileUploader {
  String requestId = UniqueKey().toString();
  web.Worker? _worker;

  LargeFileUploader() {
    js_interop.JSString str = 'upload_worker.js'.toJS;
    _worker = web.Worker(str);
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

    js_interop.JSBoxedDartObject jsStr = str.toJSBox;
    _worker?.postMessage(jsStr);

    // _worker?.addEventListener("error", (event) {} as web.EventListener?);

    // _worker?.addEventListener<String>("message", (event) {
    //   // console.log(`Received message from worker: ${event.data}`);
    // });

    // _worker?.addEventListener("error", (web.EventListener eent) {});
    // _worker?.addEventListener("message", (web.EventListener eent) {});

    // _worker?.onError.listen((event) {
    //   log("Request abort or is necessary to add file upload_worker.js inside project on folder 'web' like 'web/upload_worker.js");
    // });
    //
    // _worker?.onMessage.listen((data) {
    //   _handleCallbacks(
    //     data.data,
    //     onSendProgress: onSendProgress,
    //     onFailure: onFailure,
    //     onComplete: onComplete,
    //   );
    // });
  }

  void onCancel() {
    Map<String, dynamic> str = {
      'method': 'abort',
      'requestId': requestId,
    };

    js_interop.JSBoxedDartObject jsStr = str.toJSBox;
    _worker?.postMessage(jsStr);
  }

  void _handleCallbacks(
    dynamic data, {
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
