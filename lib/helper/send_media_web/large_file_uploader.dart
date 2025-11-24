import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

typedef UploadProgressListener = Function(int progress);
typedef UploadFailureListener = Function();
typedef UploadCompleteListener = Function(String response);
typedef OnFileSelectedListener = Function(web.File file);

class LargeFileUploader {
  String requestId = UniqueKey().toString();
  web.Worker? _worker;

  LargeFileUploader() {
    try {
      requestId = UniqueKey().toString();
    } catch (e) {
      requestId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final workerCode = _getWorkerCode();
    final blobParts = [workerCode.toJS].toJS;
    final blobOptions = web.BlobPropertyBag(type: 'application/javascript');
    final blob = web.Blob(blobParts, blobOptions);
    final blobUrl = web.URL.createObjectURL(blob);
    _worker = web.Worker(blobUrl.toJS);
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
    if (_worker == null) {
      onFailure?.call();
      return;
    }

    if (cancelFunction != null) {
      cancelFunction(onCancel);
    }

    final message = <String, Object?>{
      'method': method,
      'uploadUrl': uploadUrl,
      'data': data,
      'headers': headers,
      'requestId': requestId,
    }.jsify();

    _worker?.postMessage(message);

    _worker?.addEventListener('error', (web.Event event) {
      onFailure?.call();
    }.toJS);

    _worker?.addEventListener('message', (web.MessageEvent event) {
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
          // Ignore conversion errors
        }
      }
    }.toJS);
  }

  void onCancel() {
    final message = <String, Object?>{
      'method': 'abort',
      'requestId': requestId,
    }.jsify();
    _worker?.postMessage(message);
  }

  void _handleCallbacks(
    dynamic data, {
    required UploadProgressListener onSendProgress,
    UploadFailureListener? onFailure,
    UploadCompleteListener? onComplete,
  }) {
    if (data == null) return;

    if (data is num) {
      onSendProgress.call(data.toInt());
      return;
    }

    final dataString = data.toString();
    if (dataString == 'request failed') {
      onFailure?.call();
      return;
    }

    if (data is String) {
      onComplete?.call(data);
      return;
    }

    try {
      final jsonString = data.toString();
      onComplete?.call(jsonString);
    } catch (e) {
      onComplete?.call(dataString);
    }
  }

  String _getWorkerCode() {
    return '''
var activeRequests = {};

self.addEventListener('message', async (event) => {
  var method = event.data.method;
  var uploadUrl = event.data.uploadUrl;
  var data = event.data.data;
  var headers = event.data.headers;

  if (method === 'abort') {
    var requestId = event.data.requestId;
    var xhr = activeRequests[requestId];
    if (xhr) {
      xhr.abort();
      delete activeRequests[requestId];
    }
    return;
  }
  
  var xhr = uploadFile(method, uploadUrl, data, headers);
  activeRequests[event.data.requestId] = xhr;
});

function uploadFile(method, uploadUrl, data, headers) {
  var xhr = new XMLHttpRequest();
  var formData = new FormData();
  var uploadPercent;
  
  setData(formData, data);

  xhr.upload.addEventListener('progress', function (d) {
    if (d.lengthComputable) {
      uploadPercent = Math.floor((d.loaded / d.total) * 100);
      postMessage(uploadPercent);
    }
  }, false);

  xhr.onload = function () {
    if (xhr.status >= 200 && xhr.status < 300) {
      try {
        var response = xhr.responseText;
        if (response) {
          try {
            var jsonResponse = JSON.parse(response);
            postMessage(JSON.stringify({"data": jsonResponse}));
          } catch (e) {
            postMessage(response);
          }
        } else {
          postMessage(JSON.stringify({"data": {}}));
        }
      } catch (e) {
        postMessage(xhr.responseText || "request completed");
      }
    } else {
      try {
        var errorResponse = xhr.responseText;
        if (errorResponse) {
          try {
            var jsonError = JSON.parse(errorResponse);
            postMessage(JSON.stringify({"error": jsonError}));
          } catch (e) {
            postMessage(JSON.stringify({"error": errorResponse}));
          }
        } else {
          postMessage(JSON.stringify({"error": "Request failed with status " + xhr.status}));
        }
      } catch (e) {
        postMessage(JSON.stringify({"error": "Request failed with status " + xhr.status}));
      }
    }
  };

  xhr.onerror = function () {
    postMessage("request failed");
  };

  xhr.open(method, uploadUrl, true);
  setHeaders(xhr, headers);
  xhr.send(formData);
  return xhr;
}

function setData(formData, data) {
  for (let key in data) {
    formData.append(key, data[key]);
  }
}

function setHeaders(xhr, headers) {
  if (headers) {
    for (let key in headers) {
      if (headers.hasOwnProperty(key)) {
        xhr.setRequestHeader(key, headers[key]);
      }
    }
  }
}
''';
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
