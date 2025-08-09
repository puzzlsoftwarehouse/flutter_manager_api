import 'dart:async';
import 'dart:js_interop';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
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

    JSUint8Array bytes = (await file.readAsBytes()).toJS;

    html.File htmlFile = html.File(
      JSArray.from(bytes),
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

        print("Resposta recebida - Tipo: ${response.runtimeType}");
        print("Resposta: $response");

        // try {
        //   // Se a resposta for uma string, tentar fazer parse como JSON
        //   if (response is String) {
        //     if (response.isValidJson()) {
        //       Map<String, dynamic> data = jsonDecode(response);
        //       completer.complete(data);
        //     } else {
        //       completer.complete({'data': response});
        //     }
        //   } else {
        //     // Se não for string, usar como está
        //     completer.complete({'data': response});
        //   }
        // } catch (e) {
        //   print('Erro ao processar resposta: $e');
        //   completer.complete({'error': 'Erro ao processar resposta: $e'});
        // }
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
