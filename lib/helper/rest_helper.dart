import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:manager_api/default_api_failures.dart';
import 'package:rxdart/rxdart.dart';

class RestHelper {
  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> getRequest({
    required String url,
    Map<String, String>? headers = const {},
  }) async {
    return await tryRequest(() async {
      Response response = await Dio()
          .get(
            url,
            options: Options(
              headers: headers,
            ),
          )
          .timeout(_defaultTimeout);

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response);

      return _errorServer(
        code: response.statusCode.toString(),
        message: response.statusMessage,
      );
    });
  }

  Future<Map<String, dynamic>> postRequest({
    required String url,
    Map? body,
    Map<String, String>? headers = const {},
  }) async {
    return await tryRequest(() async {
      Response response = await Dio()
          .post(
            url,
            options: Options(
              headers: headers,
            ),
            data: body,
          )
          .timeout(_defaultTimeout);

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response);

      return _errorServer(
        code: response.statusCode.toString(),
        message: response.statusMessage,
      );
    });
  }

  Future<Map<String, dynamic>> sendMedia({
    required File file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
    CancelToken? cancelToken,
  }) async {
    return await tryRequest(() async {
      Dio dio = Dio();
      MultipartFile multipartFile = await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      );
      Map<String, dynamic> localHeaders = {
        "Content-Type": "multipart/form-data"
      };
      if (headers != null) localHeaders.addAll(headers);
      FormData formData = FormData.fromMap({'file': multipartFile});

      final Response response = await dio.post(
        '${const String.fromEnvironment("BASEAPIURL")}/media/upload',
        data: formData,
        onSendProgress: (a, b) => streamProgress?.add(((a / b) * 100).toInt()),
        queryParameters: parameters,
        cancelToken: cancelToken,
        options: Options(
          headers: localHeaders,
        ),
      );
      debugPrint(response.statusMessage.toString());
      if (response.statusCode == 200) {
        dio.close();
        return _successData(response);
      }
      log(response.data.toString());
      dio.close();

      Map<String, dynamic> body = jsonDecode(response.data);

      int? exceptionCode = body['exception_code'];
      String? errorMessage = body['detail'];

      return _errorServer(
        code: (exceptionCode ?? (response.statusCode ?? "000")).toString(),
        message: errorMessage ?? response.statusMessage,
      );
    });
  }

  Map<String, dynamic> _successData(Response response) {
    return {"data": response.data};
  }

  Map<String, dynamic> _errorServer(
      {required String code, required String? message}) {
    return {
      'error': {
        'type': 'server',
        'code': code,
        'message': message,
      }
    };
  }

  Future<Map<String, dynamic>> tryRequest(Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout:
          return {
            'error': {
              'type': 'timeout',
              'message': 'tempo excedido',
            }
          };
        case DioExceptionType.cancel:
          return {
            'error': {
              'code': DefaultAPIFailures.cancelErrorCode,
              'message': 'canceled by user',
            }
          };
        case DioExceptionType.connectionError || DioExceptionType.unknown:
          return {
            'error': {
              'message': 'no Internet connection',
            }
          };
        default:
          return {
            'error': {
              'message': e.message,
            }
          };
      }
    }
  }
}
//
// class MultipartRequestFile extends MultipartRequest {
//   final void Function(int bytes, int totalBytes)? onProgress;
//
//   MultipartRequestFile(
//     String method,
//     Uri url, {
//     this.onProgress,
//   }) : super(method, url);
//
//   @override
//   ByteStream finalize() {
//     final byteStream = super.finalize();
//     if (onProgress == null) return byteStream;
//
//     final total = contentLength;
//     var bytes = 0;
//
//     final t = StreamTransformer.fromHandlers(
//       handleData: (List<int> data, EventSink<List<int>> sink) {
//         bytes += data.length;
//         onProgress?.call(bytes, total);
//         sink.add(data);
//       },
//     );
//     final stream = byteStream.transform(t);
//     return ByteStream(stream);
//   }
// }
