import 'dart:collection';
import 'package:js_interop_utils/js_interop_utils.dart';

import 'package:web/web.dart' as html;

typedef UploadProgressListener = Function(int progress);
typedef UploadFailureListener = Function();
typedef UploadCompleteListener = Function(dynamic response);
typedef OnFileSelectedListener = Function(html.File file);

class LargeFileUploader {
  html.Worker? _worker;

  LargeFileUploader() {
    _worker = html.Worker('upload_worker.js'.toJS);
  }

  Map<String, dynamic> linkedMapToMap(
    LinkedHashMap<Object?, Object?> linkedMap,
  ) {
    return linkedMap.map((key, value) => MapEntry(key.toString(), value));
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

    Map<String, dynamic> map = {
      'method': 'upload',
      'uploadUrl': uploadUrl,
      'file': data['file'],
      'data': Map<String, dynamic>.from(data)..remove('file'),
      'headers': headers,
    };

    _worker?.postMessage(map.toJSDeep);

    _worker?.addEventListener(
      "message",
      ((html.Event event) {
        final messageData = (event as html.MessageEvent).data;
        final JSObject object = messageData as JSObject;
        final String? type = object.get("type") as String?;

        switch (type) {
          case 'progress':
            final int? progress = object.get("progress") as int?;
            onSendProgress(progress ?? 0);
            break;
          case 'success':
            final responseData = object.get("data");
            onComplete?.call(responseData);
            break;
          case 'error':
            onFailure?.call();
            break;
          case 'abort':
            break;
        }
      }.toJS),
    );

    _worker?.addEventListener(
      "error",
      ((html.Event event) {
        onFailure?.call();
      }.toJS),
    );
  }

  void onCancel() {
    _worker?.postMessage({'method': 'abort'}.toJSDeep);
  }

  void dispose() {
    _worker?.terminate();
    _worker = null;
  }
}
