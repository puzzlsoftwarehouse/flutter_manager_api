import 'package:manager_api/default_api_failures.dart';
import 'package:manager_api/models/failure/failure.dart';
import 'package:manager_api/models/resultlr/resultlr.dart';

typedef ReturnRequest = dynamic Function(Map<String, dynamic>);

class RequestAPI<ResultLR> {
  final String name;
  final ReturnRequest returnRequest;
  final List<Failure> failures;
  final SkipRequest? skipRequest;

  RequestAPI({
    required this.name,
    required this.returnRequest,
    List<Failure> failures = const <Failure>[],
    this.skipRequest,
  }) : failures = DefaultAPIFailures.failures..addAll(failures);

  Map<String, dynamic> get toJson => {};
}

class SkipRequest {
  Future<ResultLR<Failure, dynamic>> result;
  SkipRequest({required this.result});
}
