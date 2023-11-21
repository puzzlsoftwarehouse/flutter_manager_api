import 'dart:async';
import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/helper/send_media_web/large_file_uploader.dart';
import 'package:rxdart/subjects.dart';
import 'package:universal_html/html.dart' as html;

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
    html.File htmlFile = html.File(
      [await file.readAsBytes()],
      file.name,
      {'type': file.mimeType},
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
        Map<String, dynamic> data = jsonDecode(response);
        if (data['error'] != null) data = data['error'];
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
