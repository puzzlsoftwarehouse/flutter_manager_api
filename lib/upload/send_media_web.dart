import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/upload/web/web_form_upload.dart';
import 'package:manager_api/upload/web/web_multipart_upload.dart';
import 'package:rxdart/subjects.dart';

class SendMedia {
  SendMedia._();

  static Future<Map<String, dynamic>> sendMedia({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const <String, dynamic>{},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) {
    return WebFormUpload(
      file: file,
      url: url,
      parameters: parameters,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    ).start();
  }

  static Future<Map<String, dynamic>> sendMediaMultipart({
    required XFile file,
    required String url,
    Map<String, dynamic> parameters = const <String, dynamic>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) {
    return WebMultipartUpload(
      file: file,
      url: url,
      parameters: parameters,
      body: body,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    ).start();
  }
}
