import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/upload/common/upload_headers.dart';
import 'package:manager_api/upload/common/upload_result.dart';
import 'package:manager_api/upload/native/native_file_source.dart';
import 'package:manager_api/utils/failure_message_resolver.dart';
import 'package:rxdart/subjects.dart';

class NativeFormUpload {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  const NativeFormUpload({
    required this.file,
    required this.url,
    required this.parameters,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  Future<Map<String, dynamic>> start() {
    return _NativeFormUploadCoordinator(
      file: file,
      url: url,
      parameters: parameters,
      headers: headers,
      streamProgress: streamProgress,
      cancelToken: cancelToken,
    ).start();
  }
}

class _NativeFormUploadCoordinator {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  _NativeFormUploadCoordinator({
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

    final Uint8List? inMemoryBytes =
        await NativeFileSource(file).readInMemoryBytesIfNeeded();
    final TransferableTypedData? inMemoryFileBytes = inMemoryBytes == null
        ? null
        : TransferableTypedData.fromList(<Uint8List>[inMemoryBytes]);

    final _NativeFormIsolateRequest request = _NativeFormIsolateRequest(
      replyPort: receivePort.sendPort,
      filePath: file.path,
      fileName: file.name,
      inMemoryFileBytes: inMemoryFileBytes,
      url: url,
      parameters: parameters,
      headers: headers,
    );

    _isolate = await Isolate.spawn<_NativeFormIsolateRequest>(
      _NativeFormUploadWorker.run,
      request,
      errorsAreFatal: true,
    );

    _subscription = receivePort.listen(_handleEvent);
    _cancelSubscription = cancelToken?.whenCancel.asStream().listen((_) {
      _isolateCancelPort?.send(null);
      _completeResult(UploadResult.canceled());
    });

    return resultCompleter.future;
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
      _completeResult(UploadResult.success(responseData));
      return;
    }

    if (type == 'error') {
      _completeResult(
        UploadResult.failure(
          code: (event['code'] as String?) ?? '000',
          message:
              (event['message'] as String?) ?? 'Unexpected upload error',
        ),
      );
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
}

class _NativeFormUploadWorker {
  final _NativeFormIsolateRequest request;

  const _NativeFormUploadWorker(this.request);

  static Future<void> run(_NativeFormIsolateRequest request) async {
    await _NativeFormUploadWorker(request)._run();
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
        receiveTimeout: const Duration(hours: 2),
        sendTimeout: const Duration(hours: 2),
      ),
    );

    try {
      final MultipartFile multipartFile = await _createMultipartFile();
      final FormData formData = FormData.fromMap(<String, Object>{
        'file': multipartFile,
      });

      final Response<dynamic> response = await uploadClient.post<dynamic>(
        request.url,
        data: formData,
        queryParameters: request.parameters,
        options: Options(
          headers: UploadHeaders.withoutContentType(request.headers),
        ),
        cancelToken: cancelToken,
        onSendProgress: (int sent, int total) {
          final int progress = total <= 0 ? 0 : ((sent / total) * 100).toInt();
          onProgress(progress.clamp(0, 100));
        },
      );

      if (UploadResult.isSuccessStatus(response.statusCode)) {
        return UploadResult.success(response.data);
      }

      return UploadResult.fromResponse(response);
    } on DioException catch (exception) {
      return UploadResult.fromDioException(exception);
    } catch (exception) {
      return UploadResult.failure(
        code: '000',
        message: FailureMessageResolver.summarize(exception.toString()),
      );
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
      throw StateError('Invalid file for upload.');
    }

    if (!await File(filePath).exists()) {
      throw StateError('File not found for upload.');
    }

    return MultipartFile.fromFile(filePath, filename: request.fileName);
  }
}

class _NativeFormIsolateRequest {
  final SendPort replyPort;
  final String filePath;
  final String fileName;
  final TransferableTypedData? inMemoryFileBytes;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;

  const _NativeFormIsolateRequest({
    required this.replyPort,
    required this.filePath,
    required this.fileName,
    required this.inMemoryFileBytes,
    required this.url,
    required this.parameters,
    required this.headers,
  });
}
