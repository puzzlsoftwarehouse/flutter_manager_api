import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
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
  SendPort? _isolateCancelPort;

  Future<Map<String, dynamic>> start() async {
    final ReceivePort receivePort = ReceivePort();
    final Completer<Map<String, dynamic>> resultCompleter =
        Completer<Map<String, dynamic>>();

    _receivePort = receivePort;
    _resultCompleter = resultCompleter;

    final TransferableTypedData? inMemoryFileBytes =
        await _readInMemoryFileBytesIfNeeded();

    final _SendMediaIsolateRequest request = _SendMediaIsolateRequest(
      replyPort: receivePort.sendPort,
      filePath: file.path,
      fileName: file.name,
      inMemoryFileBytes: inMemoryFileBytes,
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
      _isolateCancelPort?.send(null);
      _completeResult(
        _failureMap(
          code: DefaultAPIFailures.cancelErrorCode,
          message: 'canceled by user',
        ),
      );
    });

    return resultCompleter.future;
  }

  Future<TransferableTypedData?> _readInMemoryFileBytesIfNeeded() async {
    if (!_hasLocalFileOnDisk()) {
      final Uint8List fileBytes = await file.readAsBytes();
      return TransferableTypedData.fromList(<Uint8List>[fileBytes]);
    }

    return null;
  }

  bool _hasLocalFileOnDisk() {
    final String filePath = file.path;
    if (filePath.isEmpty) {
      return false;
    }

    if (!_isFilesystemPath(filePath)) {
      return false;
    }

    return File(filePath).existsSync();
  }

  bool _isFilesystemPath(String path) {
    if (path.startsWith('/')) {
      return true;
    }

    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path)) {
      return true;
    }

    return false;
  }

  void _handleEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) {
      return;
    }

    final String? type = event['type'] as String?;
    if (type == 'cancel_ready') {
      _isolateCancelPort = event['cancelPort'] as SendPort?;
      return;
    }

    if (type == 'progress') {
      final int progress = (event['value'] as num?)?.toInt() ?? 0;
      streamProgress?.add(progress.clamp(0, 100));
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
    _isolateCancelPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
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
    final CancelToken cancelToken = CancelToken();
    final ReceivePort cancelReceivePort = ReceivePort();
    final StreamSubscription<dynamic> cancelSubscription =
        cancelReceivePort.listen((_) {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel();
          }
        });

    request.replyPort.send(<String, Object?>{
      'type': 'cancel_ready',
      'cancelPort': cancelReceivePort.sendPort,
    });

    try {
      final Map<String, dynamic> result = await _performUpload(
        cancelToken: cancelToken,
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
    } finally {
      await cancelSubscription.cancel();
      cancelReceivePort.close();
    }
  }

  Future<Map<String, dynamic>> _performUpload({
    required CancelToken cancelToken,
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
      final MultipartFile multipartFile = await _createMultipartFile();
      final FormData formData = FormData.fromMap(<String, Object>{
        'file': multipartFile,
      });
      final Map<String, String> requestHeaders = _buildRequestHeaders();

      final Response<dynamic> response = await uploadClient.post<dynamic>(
        request.url,
        data: formData,
        queryParameters: request.parameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
        onSendProgress: (int sent, int total) {
          final int progress = total <= 0 ? 0 : ((sent / total) * 100).toInt();
          onProgress(progress.clamp(0, 100));
        },
      );

      final int? statusCode = response.statusCode;
      if (statusCode != null && statusCode >= 200 && statusCode < 300) {
        final Object? responseData = response.data;
        if (responseData is Map<Object?, Object?>) {
          return <String, dynamic>{
            'data': Map<String, dynamic>.from(responseData),
          };
        }
        return <String, dynamic>{'data': responseData};
      }

      return _failureFromResponse(response);
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
        return _failureMap(
          code: 'noConnection',
          message: 'no Internet connection',
        );
      }

      final Response<dynamic>? errorResponse = exception.response;
      if (errorResponse != null) {
        return _failureFromResponse(errorResponse);
      }

      return _failureMap(
        code: '000',
        message: exception.message ?? 'Unknown server error',
      );
    } catch (exception) {
      return _failureMap(code: '000', message: exception.toString());
    } finally {
      uploadClient.close(force: true);
    }
  }

  Future<MultipartFile> _createMultipartFile() async {
    final TransferableTypedData? inMemoryFileBytes = request.inMemoryFileBytes;
    if (inMemoryFileBytes != null) {
      final Uint8List fileBytes = inMemoryFileBytes.materialize().asUint8List();
      return MultipartFile.fromBytes(fileBytes, filename: request.fileName);
    }

    final String filePath = request.filePath;
    if (filePath.isEmpty) {
      throw StateError('Arquivo inválido para upload.');
    }

    final File localFile = File(filePath);
    if (!await localFile.exists()) {
      throw StateError('Arquivo não encontrado para upload.');
    }

    return MultipartFile.fromFile(filePath, filename: request.fileName);
  }

  Map<String, String> _buildRequestHeaders() {
    final Map<String, String> requestHeaders = <String, String>{};
    final Map<String, String>? customHeaders = request.headers;
    if (customHeaders == null) {
      return requestHeaders;
    }

    for (final MapEntry<String, String> header in customHeaders.entries) {
      if (header.key.toLowerCase() == 'content-type') {
        continue;
      }
      requestHeaders[header.key] = header.value;
    }

    return requestHeaders;
  }

  Map<String, dynamic> _failureFromResponse(Response<dynamic> response) {
    final int statusCode = response.statusCode ?? 0;
    final Object? responseData = response.data;

    if (responseData is Map<Object?, Object?>) {
      final Map<String, dynamic> errorMap =
          Map<String, dynamic>.from(responseData);
      return _failureMap(
        code:
            errorMap['exception_code']?.toString() ?? statusCode.toString(),
        message:
            errorMap['detail']?.toString() ??
            errorMap['message']?.toString() ??
            _friendlyUploadFailureMessage(
              statusCode: statusCode,
              fallbackMessage: response.statusMessage ?? 'Unknown server error',
            ),
      );
    }

    return _failureMap(
      code: statusCode.toString(),
      message: _friendlyUploadFailureMessage(
        statusCode: statusCode,
        fallbackMessage:
            responseData?.toString() ??
            response.statusMessage ??
            'Unknown server error',
      ),
    );
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
  final TransferableTypedData? inMemoryFileBytes;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;

  const _SendMediaIsolateRequest({
    required this.replyPort,
    required this.filePath,
    required this.fileName,
    required this.inMemoryFileBytes,
    required this.url,
    required this.parameters,
    required this.headers,
  });
}
