import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:manager_api/upload/common/upload_result.dart';
import 'package:manager_api/upload/web/web_upload_blob_loader.dart';
import 'package:manager_api/upload/web/web_upload_worker.dart';
import 'package:rxdart/subjects.dart';
import 'package:web/web.dart' as web;

class WebFormUpload {
  final XFile file;
  final String url;
  final Map<String, dynamic> parameters;
  final Map<String, String>? headers;
  final BehaviorSubject<int>? streamProgress;
  final CancelToken? cancelToken;

  const WebFormUpload({
    required this.file,
    required this.url,
    required this.parameters,
    required this.headers,
    required this.streamProgress,
    required this.cancelToken,
  });

  Future<Map<String, dynamic>> start() async {
    const WebUploadBlobLoader blobLoader = WebUploadBlobLoader();
    final Uri uploadUri = Uri.parse(url).replace(
      queryParameters: parameters.map(
        (String key, dynamic value) => MapEntry(key, value.toString()),
      ),
    );

    final web.Blob fileBlob = await blobLoader.load(file);
    final WebUploadWorker uploadWorker = WebUploadWorker();
    StreamSubscription<void>? cancelSubscription;
    void Function()? cancelUpload;

    cancelSubscription = cancelToken?.whenCancel.asStream().listen((_) {
      cancelUpload?.call();
    });

    try {
      return await uploadWorker.upload(
        uploadUrl: uploadUri.toString(),
        fileBlob: fileBlob,
        fileName: file.name,
        headers: headers,
        onProgress: streamProgress?.add,
        registerCancel: (void Function() onCancel) {
          cancelUpload = onCancel;
        },
      );
    } catch (error) {
      return UploadResult.fromCaughtError(error);
    } finally {
      await cancelSubscription?.cancel();
      uploadWorker.dispose();
    }
  }
}
