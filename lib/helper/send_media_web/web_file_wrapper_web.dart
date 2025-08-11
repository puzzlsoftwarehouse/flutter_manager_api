import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

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
    return {};
  }
}
