import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:js_interop_utils/js_interop_utils.dart';
import 'package:manager_api/extension.dart';
import 'package:manager_api/helper/send_media_web/large_file_uploader.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as html;

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

    Uint8List bytes = await file.readAsBytes();

    html.File htmlFile = html.File(
      [bytes.toJS].toJS,
      file.name,
      html.FilePropertyBag(type: file.mimeType ?? 'application/octet-stream'),
    );

    Uri uri = Uri.parse(url);
    uri = uri.replace(queryParameters: parameters);

    LargeFileUploader().upload(
      method: 'upload',
      uploadUrl: uri.toString(),
      data: {"file": htmlFile},
      headers: headers,
      onSendProgress: (progress) => streamProgress?.add(progress),
      onComplete: (response) {
        if (completer.isCompleted) return;

        try {
          if (response is String && response.isValidJson()) {
            Map<String, dynamic> data = jsonDecode(response);
            completer.complete(data);
            return;
          }

          completer.complete(response);
        } catch (e) {
          completer.complete({'error': 'Erro ao processar resposta: $e'});
        }
      },
      onFailure: () {
        if (completer.isCompleted) return;
        completer.complete({'error': 'Upload falhou'});
      },
      cancelFunction: (onCancel) {
        cancelToken?.whenCancel.then((value) {
          onCancel();
        });
      },
    );
    return await completer.future;
  }
}
