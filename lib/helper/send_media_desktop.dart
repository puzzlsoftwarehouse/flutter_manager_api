import 'dart:convert';
import 'dart:developer';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/subjects.dart';

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
    MultipartFile dioFile;

    if (kIsWeb) {
      dioFile = MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: file.name,
      );
    } else {
      dioFile = await MultipartFile.fromFile(
        file.path,
        filename: file.name,
      );
    }

    Dio dio = Dio();
    Map<String, dynamic> localHeaders = {"Content-Type": "multipart/form-data"};
    if (headers != null) localHeaders.addAll(headers);
    FormData formData = FormData.fromMap({'file': dioFile});

    final Response response = await dio.post(
      url,
      data: formData,
      onSendProgress: (a, b) => streamProgress?.add(((a / b) * 100).toInt()),
      queryParameters: parameters,
      cancelToken: cancelToken,
      options: Options(
        headers: localHeaders,
      ),
    );
    if (response.statusCode == 200) {
      dio.close();
      return {"data": response.data};
    }
    log(response.data.toString());
    dio.close();

    Map<String, dynamic> body = jsonDecode(response.data);
    if (body['exception_code'] == null) {
      body['exception_code'] = (response.statusCode ?? "000");
    }
    body['exception_code'] = body['exception_code'].toString();

    if (body['detail'] == null) {
      body['detail'] = response.statusMessage;
    }
    return body;
  }
}
