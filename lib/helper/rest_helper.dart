import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart';
import 'package:manager_api/requests/rest_request.dart';
import 'package:rxdart/rxdart.dart';

class RestHelper {
  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> getRequest({
    required String url,
    Map<String, String>? headers = const {},
    required RequestResponseBodyType bodyType,
  }) async {
    return await tryRequest(() async {
      Response response =
          await get(Uri.parse(url), headers: headers).timeout(_defaultTimeout);

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response, bodyType);

      return _errorServer(
        code: response.statusCode,
        message: response.reasonPhrase,
      );
    });
  }

  Future<Map<String, dynamic>> postRequest({
    required String url,
    Map? body,
    Map<String, String>? headers = const {},
    required RequestResponseBodyType bodyType,
  }) async {
    return await tryRequest(() async {
      Response response = await post(
        Uri.parse(url),
        headers: headers,
        body: body,
      ).timeout(_defaultTimeout);

      bool isSuccess = response.statusCode == 200;
      if (isSuccess) return _successData(response, bodyType);

      return _errorServer(
        code: response.statusCode,
        message: response.reasonPhrase,
      );
    });
  }

  Future<Map<String, dynamic>> sendMedia({
    required MultipartFile file,
    required String url,
    Map<String, dynamic> parameters = const {},
    Map<String, String>? headers,
    BehaviorSubject<int>? streamProgress,
  }) async {
    Uri uri = Uri.parse(url).replace(queryParameters: parameters);

    Map<String, String> localHeaders = {"Content-Type": "multipart/form-data"};
    localHeaders.addAll(headers ?? {});
    final request = MultipartRequestFile(
      'POST',
      uri,
      onProgress: (bytes, totalBytes) {
        if (streamProgress != null) {
          streamProgress.add(((bytes * 100) / totalBytes).round());
        }
      },
    );
    request
      ..headers.addAll(localHeaders)
      ..files.add(file);
    return await tryRequest(() async {
      StreamedResponse stream = await request.send();

      final response = await Response.fromStream(stream);

      if (response.statusCode == 200) {
        if (!request.finalized) request.finalize();
        return _successData(response, RequestResponseBodyType.json);
      }
      log(response.body.toString());
      if (!request.finalized) request.finalize();

      Map<String, dynamic> body = jsonDecode(response.body);

      int? exceptionCode = body['exception_code'];
      String? errorMessage = body['detail'];

      return _errorServer(
        code: exceptionCode ?? response.statusCode,
        message: errorMessage ?? response.reasonPhrase,
      );
    });
  }

  Map<String, dynamic> _successData(
      Response response, RequestResponseBodyType type) {
    if (type == RequestResponseBodyType.json) {
      return {"data": jsonDecode(response.body)};
    }
    return {"data": response.bodyBytes};
  }

  Map<String, dynamic> _errorServer(
      {required int code, required String? message}) {
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
    } on TimeoutException {
      return {
        'error': {
          'type': 'timeout',
          'message': 'tempo excedido',
        }
      };
    } on SocketException {
      return {
        'error': {
          'message': 'no Internet connection',
        }
      };
    } on HttpException {
      return {
        'error': {
          'message': 'canceled by user',
        }
      };
    } on ClientException {
      return {
        'error': {
          'message': 'canceled by user',
        }
      };
    }
  }
}

class MultipartRequestFile extends MultipartRequest {
  final void Function(int bytes, int totalBytes)? onProgress;

  MultipartRequestFile(
    String method,
    Uri url, {
    this.onProgress,
  }) : super(method, url);

  @override
  ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;

    final total = contentLength;
    var bytes = 0;

    final t = StreamTransformer.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytes += data.length;
        onProgress?.call(bytes, total);
        sink.add(data);
      },
    );
    final stream = byteStream.transform(t);
    return ByteStream(stream);
  }
}
