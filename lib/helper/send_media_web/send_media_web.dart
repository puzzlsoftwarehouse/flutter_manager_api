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
    Map<String, dynamic> parameters = const <String, dynamic>{},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();

    try {
      final Uint8List bytes = await file.readAsBytes();
      final JSArray<JSAny> blobParts = [bytes.toJS].toJS;
      final web.FilePropertyBag filePropertyBag = web.FilePropertyBag(
          type: file.mimeType ?? 'application/octet-stream');
      final web.File htmlFile = web.File(blobParts, file.name, filePropertyBag);

      final Uri uri = Uri.parse(url).replace(queryParameters: parameters);
      final LargeFileUploader uploader = LargeFileUploader();

      uploader.upload(
        method: 'POST',
        uploadUrl: uri.toString(),
        data: {"file": htmlFile},
        headers: headers,
        onSendProgress: (progress) => streamProgress?.add(progress),
        onComplete: (String response) {
          if (completer.isCompleted) return;

          if (response.isValidJson()) {
            final Map<String, dynamic> data =
                jsonDecode(response) as Map<String, dynamic>;
            completer.complete(data);
            return;
          }

          completer.complete(<String, dynamic>{'error': response});
        },
        onFailure: (String? error) {
          if (!completer.isCompleted) {
            completer.complete(<String, dynamic>{
              'error': error ?? 'Upload failed'
            });
          }
        },
        cancelFunction: (onCancel) {
          cancelToken?.whenCancel.then((_) => onCancel());
        },
      );

      return await completer.future;
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete({'error': 'Erro ao processar upload: $e'});
      }
      return completer.future;
    }
  }
}
