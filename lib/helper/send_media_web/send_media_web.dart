import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/extension.dart';
import 'package:manager_api/helper/send_media_web/large_file_uploader.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class SendMedia {
  SendMedia._();

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

    Uint8List array = await file.readAsBytes();

    JSArray<JSUint8Array> jsArray = JSArray.from(array.toJS);

    web.File htmlFile = web.File(
      jsArray,
      file.name,
      web.FilePropertyBag(
        type: file.mimeType ?? "application/octet-stream",
        endings: "transparent",
      ),
    );

    Uri uri = Uri.parse(url);
    uri = uri.replace(queryParameters: parameters);

    LargeFileUploader().upload(
      method: 'POST',
      uploadUrl: uri.toString(),
      data: {"file": htmlFile},
      headers: headers,
      onSendProgress: (progress) => streamProgress?.add(progress),
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
      cancelFunction: (onCancel) {
        cancelToken?.whenCancel.then((value) {
          onCancel();
        });
      },
    );
    return await completer.future;
  }
}
