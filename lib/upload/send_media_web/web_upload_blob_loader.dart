import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

class WebUploadBlobLoader {
  const WebUploadBlobLoader();

  Future<web.Blob> load(XFile file) async {
    final String filePath = file.path;

    if (_canLoadBlobFromPath(filePath)) {
      try {
        return await _loadBlobFromPath(filePath);
      } catch (_) {}
    }

    if (!_isBrowserResolvablePath(filePath)) {
      return _loadBlobFromBytes(file);
    }

    try {
      return await _loadBlobFromBytes(file);
    } catch (_) {
      return await _loadBlobFromPath(filePath);
    }
  }

  bool _isBrowserResolvablePath(String path) {
    return _canLoadBlobFromPath(path);
  }

  bool _canLoadBlobFromPath(String path) {
    if (path.isEmpty) {
      return false;
    }

    return path.startsWith('blob:') ||
        path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://');
  }

  Future<web.Blob> _loadBlobFromPath(String path) async {
    final Completer<web.Blob> blobCompleter = Completer<web.Blob>();
    final web.XMLHttpRequest request = web.XMLHttpRequest();

    request.open('GET', path, true);
    request.responseType = 'blob';

    request.onLoad.first.then((_) {
      final JSAny? response = request.response;
      if (response == null) {
        blobCompleter.completeError(
          StateError('Resposta do arquivo inválida para upload.'),
        );
        return;
      }
      blobCompleter.complete(response as web.Blob);
    });

    request.onError.first.then((_) {
      blobCompleter.completeError(
        StateError('Não foi possível carregar o arquivo para upload.'),
      );
    });

    request.send();
    return blobCompleter.future;
  }

  Future<web.Blob> _loadBlobFromBytes(XFile file) async {
    final Uint8List fileBytes = await file.readAsBytes();
    return _createBlobFromBytes(fileBytes, file.mimeType);
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
}
