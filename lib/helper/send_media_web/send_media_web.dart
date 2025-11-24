import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/extension.dart';
import 'package:manager_api/helper/send_media_web/large_file_uploader.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as web;

class SendMediaWeb {
  SendMediaWeb._();

  static Future<Map<String, dynamic>> sendMedia({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      completer.complete({'error': 'Erro ao ler arquivo: $e'});
      return completer.future;
    }

    web.File htmlFile;
    try {
      final blobParts = [bytes.toJS].toJS;
      final filePropertyBag =
          web.FilePropertyBag(type: file.mimeType ?? 'application/octet-stream');
      htmlFile = web.File(blobParts, file.name, filePropertyBag);
    } catch (e) {
      completer.complete({'error': 'Erro ao criar web.File: $e'});
      return completer.future;
    }

    Uri uri;
    try {
      uri = Uri.parse(url);
      uri = uri.replace(queryParameters: parameters);
    } catch (e) {
      completer.complete({'error': 'Erro ao parsear URL: $e'});
      return completer.future;
    }

    LargeFileUploader uploader;
    try {
      uploader = LargeFileUploader();
    } catch (e) {
      completer.complete({'error': 'Erro ao criar LargeFileUploader: $e'});
      return completer.future;
    }

    try {
      uploader.upload(
        method: 'POST',
        uploadUrl: uri.toString(),
        data: {"file": htmlFile},
        headers: headers,
        onSendProgress: (progress) {
          streamProgress?.add(progress);
        },
        onComplete: (response) {
          if (completer.isCompleted) return;

          if (response.isValidJson()) {
            Map<String, dynamic> data = jsonDecode(response);
            if (data['error'] != null) data = data['error'];
            completer.complete(data);
            return;
          }

          Map<String, dynamic> data = {'error': response};
          completer.complete(data);
        },
        onFailure: () {
          if (completer.isCompleted) return;
          completer.complete({'error': 'Upload failed'});
        },
        cancelFunction: (onCancel) {
          cancelToken?.whenCancel.then((value) {
            onCancel();
          });
        },
      );
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete({'error': 'Erro ao chamar upload: $e'});
      }
    }

    try {
      return await completer.future;
    } catch (e) {
      return {'error': 'Erro ao aguardar resultado: $e'};
    }
  }
}
