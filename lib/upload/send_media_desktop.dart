import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:manager_api/default_api_failures.dart';
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
  }) async {
    final _NativeSendMediaCoordinator coordinator = _NativeSendMediaCoordinator(
      file: file,
      url: url,
      parameters: parameters,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    );
    return coordinator.start();
  }
}

class _NativeSendMediaCoordinator {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  _NativeSendMediaCoordinator({
    required this.file,
    required this.url,
    required this.parameters,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  Isolate? _isolate;
  Completer<Map<String, dynamic>>? _resultCompleter;
  StreamSubscription<void>? _cancelSubscription;

  Future<Map<String, dynamic>> start() async {
    final ReceivePort receivePort = ReceivePort();
    final Completer<Map<String, dynamic>> resultCompleter =
        Completer<Map<String, dynamic>>();
    final Uint8List? fileBytes = await _readFileBytesIfNeeded();

    _receivePort = receivePort;
    _resultCompleter = resultCompleter;

    final _SendMediaIsolateRequest request = _SendMediaIsolateRequest(
      replyPort: receivePort.sendPort,
      filePath: file.path,
      fileName: file.name,
      fileBytes: fileBytes == null
          ? null
          : TransferableTypedData.fromList(<Uint8List>[fileBytes]),
      url: url,
      parameters: parameters,
      headers: headers,
    );

    final Isolate isolate = await Isolate.spawn<_SendMediaIsolateRequest>(
      _NativeSendMediaWorker.run,
      request,
      errorsAreFatal: true,
    );
    _isolate = isolate;

    _subscription = receivePort.listen(_handleEvent);
    _cancelSubscription = cancelToken?.whenCancel.asStream().listen((_) {
      _completeResult(_failureMap(
        code: DefaultAPIFailures.cancelErrorCode,
        message: 'canceled by user',
      ));
    });

    return resultCompleter.future;
  }

  void _handleEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) {
      return;
    }

    final String? type = event['type'] as String?;
    if (type == 'progress') {
      final int progress = (event['value'] as num?)?.toInt() ?? 0;
      streamProgress?.add(progress);
      return;
    }

    if (type == 'success') {
      final Map<String, dynamic> responseData = Map<String, dynamic>.from(
        (event['data'] as Map<Object?, Object?>?) ?? <Object?, Object?>{},
      );
      _completeResult(<String, dynamic>{'data': responseData});
      return;
    }

    if (type == 'error') {
      final String code = (event['code'] as String?) ?? '000';
      final String message = (event['message'] as String?) ?? 'Unknown error';
      _completeResult(_failureMap(code: code, message: message));
    }
  }

  void _completeResult(Map<String, dynamic> result) {
    final Completer<Map<String, dynamic>>? resultCompleter = _resultCompleter;
    if (resultCompleter != null && !resultCompleter.isCompleted) {
      resultCompleter.complete(result);
    }
    _disposeBackgroundResources();
  }

  void _disposeBackgroundResources() {
    _subscription?.cancel();
    _subscription = null;
    _cancelSubscription?.cancel();
    _cancelSubscription = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  Future<Uint8List?> _readFileBytesIfNeeded() async {
    final String filePath = file.path;
    if (filePath.isEmpty) {
      return file.readAsBytes();
    }

    final File localFile = File(filePath);
    final bool fileExists = localFile.existsSync();
    if (fileExists) {
      return null;
    }

    return file.readAsBytes();
  }

  Map<String, dynamic> _failureMap({
    required String code,
    required String message,
  }) {
    return <String, dynamic>{
      'exception_code': code,
      'detail': message,
    };
  }
}

class _NativeSendMediaWorker {
  final _SendMediaIsolateRequest request;

  const _NativeSendMediaWorker(this.request);

  static Future<void> run(_SendMediaIsolateRequest request) async {
    final _NativeSendMediaWorker worker = _NativeSendMediaWorker(request);
    await worker._run();
  }

  Future<void> _run() async {
    try {
      final Uint8List? fileBytes = request.fileBytes?.materialize().asUint8List();
      final Map<String, dynamic> result = await _performUpload(
        filePath: request.filePath,
        fileName: request.fileName,
        fileBytes: fileBytes,
        url: request.url,
        parameters: request.parameters,
        headers: request.headers,
        onProgress: (int progress) {
          request.replyPort.send(<String, Object>{
            'type': 'progress',
            'value': progress,
          });
        },
      );

      if (result['data'] != null) {
        request.replyPort.send(<String, Object?>{
          'type': 'success',
          'data': result['data'],
        });
        return;
      }

      request.replyPort.send(<String, Object?>{
        'type': 'error',
        'code': result['exception_code'],
        'message': result['detail'],
      });
    } catch (exception) {
      request.replyPort.send(<String, Object?>{
        'type': 'error',
        'code': '000',
        'message': exception.toString(),
      });
    }
  }

  Future<Map<String, dynamic>> _performUpload({
    required String filePath,
    required String fileName,
    required Uint8List? fileBytes,
    required String url,
    required Map<String, dynamic> parameters,
    required Map<String, String>? headers,
    required void Function(int progress) onProgress,
  }) async {
    final Dio uploadClient = Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 30),
      ),
    );
    try {
      final MultipartFile multipartFile = fileBytes != null
          ? MultipartFile.fromBytes(fileBytes, filename: fileName)
          : await MultipartFile.fromFile(filePath, filename: fileName);
      final FormData formData = FormData.fromMap(<String, Object>{
        'file': multipartFile,
      });
      final Map<String, String> requestHeaders = <String, String>{
        'Content-Type': 'multipart/form-data',
        ...?headers,
      };

      final Response<dynamic> response = await uploadClient.post<dynamic>(
        url,
        data: formData,
        queryParameters: parameters,
        options: Options(headers: requestHeaders),
        onSendProgress: (int sent, int total) {
          final int progress = total <= 0 ? 0 : ((sent / total) * 100).toInt();
          onProgress(progress.clamp(0, 100));
        },
      );

      if (response.statusCode == 200) {
        return <String, dynamic>{'data': response.data};
      }

      return _failureMap(
        code: (response.statusCode ?? 0).toString(),
        message: _friendlyUploadFailureMessage(
          statusCode: response.statusCode ?? 0,
          fallbackMessage: response.statusMessage ?? 'Unknown server error',
        ),
      );
    } on DioException catch (exception) {
      if (exception.type == DioExceptionType.cancel) {
        return _failureMap(
          code: DefaultAPIFailures.cancelErrorCode,
          message: 'canceled by user',
        );
      }

      if (exception.type == DioExceptionType.connectionTimeout ||
          exception.type == DioExceptionType.receiveTimeout ||
          exception.type == DioExceptionType.sendTimeout) {
        return _failureMap(code: 'timeout', message: 'tempo excedido');
      }

      if (exception.type == DioExceptionType.connectionError ||
          exception.type == DioExceptionType.unknown) {
        return _failureMap(code: 'noConnection', message: 'no Internet connection');
      }

      final dynamic responseData = exception.response?.data;
      if (responseData is Map<Object?, Object?>) {
        final String code =
            responseData['exception_code']?.toString() ??
            (exception.response?.statusCode ?? '000').toString();
        final String message =
            responseData['detail']?.toString() ??
            exception.response?.statusMessage ??
            'Unknown server error';
        return _failureMap(code: code, message: message);
      }

      return _failureMap(
        code: (exception.response?.statusCode ?? '000').toString(),
        message: _friendlyUploadFailureMessage(
          statusCode: exception.response?.statusCode ?? 0,
          fallbackMessage:
              responseData?.toString() ??
              exception.response?.statusMessage ??
              'Unknown server error',
        ),
      );
    } catch (exception) {
      return _failureMap(code: '000', message: exception.toString());
    } finally {
      uploadClient.close(force: true);
    }
  }

  Map<String, dynamic> _failureMap({
    required String code,
    required String message,
  }) {
    return <String, dynamic>{
      'exception_code': code,
      'detail': message,
    };
  }

  String _friendlyUploadFailureMessage({
    required int statusCode,
    required String fallbackMessage,
  }) {
    if (statusCode == 413) {
      return 'This file is larger than the server upload limit.';
    }
    return fallbackMessage;
  }
}

class _SendMediaIsolateRequest {
  final SendPort replyPort;
  final String filePath;
  final String fileName;
  final TransferableTypedData? fileBytes;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;

  const _SendMediaIsolateRequest({
    required this.replyPort,
    required this.filePath,
    required this.fileName,
    required this.fileBytes,
    required this.url,
    required this.parameters,
    required this.headers,
  });
}
