import 'package:manager_api/requests/request_api.dart';
import 'package:rxdart/rxdart.dart';

enum RequestRestType { get, post, put, delete }

enum BodyType { json, bytes }

enum RequestResponseBodyType { json, bytes }

class RestRequest<ResultLR> extends RequestAPI<ResultLR> {
  final RequestRestType type;
  final String url;
  final Map<String, String>? headers;
  final Map<String, dynamic>? body;

  final String? path;
  final BehaviorSubject<int>? streamProgress;
  final Map<String, dynamic>? parameters;
  final RequestResponseBodyType bodyResponseType;
  final BodyType bodyType;

  RestRequest({
    required super.name,
    required this.type,
    required this.url,
    required super.returnRequest,
    super.skipRequest,
    this.headers,
    this.body,
    this.path,
    this.streamProgress,
    this.parameters,
    this.bodyResponseType = RequestResponseBodyType.json,
    this.bodyType = BodyType.json,
  }) : assert(
          !(bodyType == BodyType.bytes &&
              (body == null || !body.containsKey('file'))),
          'The "body" field must contain the key "file" when the "bodyType" is "BodyType.bytes".',
        );

  factory RestRequest.fromJson(Map<String, dynamic> json) => RestRequest(
        name: json['name'],
        type: json['type'],
        url: json['url'],
        headers: json['headers'],
        body: json['body'],
        skipRequest: json['skipRequest'],
        returnRequest: json['returnRequest'],
        path: json['path'],
        streamProgress: json['streamProgress'],
        parameters: json['parameters'],
        bodyResponseType: json['bodyResponseType'],
        bodyType: json['bodyType'],
      );

  @override
  Map<String, dynamic> get toJson => {
        "name": name,
        "type": type,
        "url": url,
        "headers": headers,
        "body": body,
        "skipRequest": skipRequest,
        "returnRequest": returnRequest,
        "typeAPI": "rest",
        "path": path,
        "streamProgress": streamProgress,
        "parameters": parameters,
        "bodyResponseType": bodyResponseType,
        "bodyType": bodyType,
      };
}
