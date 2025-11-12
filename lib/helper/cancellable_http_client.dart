import 'package:http/http.dart' as http;
import 'package:manager_api/utils/graphql_cancel_token.dart';

class CancellableHttpClient extends http.BaseClient {
  final GraphQLCancelToken _cancelToken;
  http.Client? _innerClient;
  bool _isClosed = false;

  CancellableHttpClient(this._cancelToken) : _innerClient = http.Client() {
    _cancelToken.whenCancelled.then((_) {
      _closeClient();
    });
  }

  void _closeClient() {
    if (!_isClosed && _innerClient != null) {
      _isClosed = true;
      _innerClient!.close();
      _innerClient = null;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_cancelToken.isCancelled || _isClosed) {
      throw Exception('Request cancelled');
    }

    if (_innerClient == null) {
      throw Exception('Request cancelled');
    }

    final future = _innerClient!.send(request);

    return future.then((response) {
      if (_cancelToken.isCancelled || _isClosed) {
        response.stream.listen(null).cancel();
        throw Exception('Request cancelled');
      }
      return response;
    }).catchError((error) {
      if (_cancelToken.isCancelled || _isClosed) {
        _closeClient();
        throw Exception('Request cancelled');
      }
      throw error;
    });
  }

  @override
  void close() {
    _closeClient();
  }
}
