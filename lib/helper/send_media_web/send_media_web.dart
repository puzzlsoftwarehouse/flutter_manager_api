import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/helper/send_media_web/chunk.dart';
import 'package:rxdart/subjects.dart';

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

    var upChunkUpload = UpChunk(
      endPoint:
          Uri.decodeFull(
            Uri(path: url, queryParameters: parameters).toString(),
          ).toString(),
      headers: headers!,
      file: file,
      onProgress: (progress) {
        print('Upload progress: ${progress.ceil()}%');

        streamProgress?.add(progress.toInt());
      },
      onError: (String message, int chunk, int attempts) {
        print('UpChunk error 💥 🙀:');
        print(' - Message: $message');
        print(' - Chunk: $chunk');
        print(' - Attempts: $attempts');
      },
      onSuccess: () {
        print('Upload complete! 👋');
      },
    );

    // Uint8List bytes = await file.readAsBytes();
    //
    // html.File htmlFile = html.File(
    //   [bytes.toJS].toJS,
    //   file.name,
    //   html.FilePropertyBag(type: file.mimeType ?? 'application/octet-stream'),
    // );
    //
    // Uri uri = Uri.parse(url);
    // uri = uri.replace(queryParameters: parameters);
    //
    // LargeFileUploader().upload(
    //   method: 'upload',
    //   uploadUrl: uri.toString(),
    //   data: {"file": htmlFile},
    //   headers: headers,
    //   onSendProgress: (progress) => streamProgress?.add(progress),
    //   onComplete: (response) {
    //     if (completer.isCompleted) return;
    //
    //     try {
    //       if (response is String) {
    //         Map<String, dynamic> data = jsonDecode(response);
    //         completer.complete({"data": data});
    //         return;
    //       }
    //
    //       Map<String, dynamic> mapResponseLinkedMap =
    //           response.cast<String, dynamic>();
    //       completer.complete({"data": mapResponseLinkedMap});
    //     } catch (e) {
    //       completer.complete({'error': 'Erro ao processar resposta: $e'});
    //     }
    //   },
    //   onFailure: () {
    //     if (completer.isCompleted) return;
    //     completer.complete({'error': 'Upload falhou'});
    //   },
    //   cancelFunction: (onCancel) {
    //     cancelToken?.whenCancel.then((value) {
    //       onCancel();
    //     });
    //   },
    // );
    return await completer.future;
  }
}
