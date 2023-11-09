import 'package:manager_api/requests/graphql_request.dart';
import 'package:flutter/services.dart';
import 'package:manager_api/utils/string_converter.dart';

class GraphQLRead {
  GraphQLRead._();

  static Future<String> get({
    required String path,
    required RequestGraphQLType type,
    required String requestName,
  }) async {
    String lineIncrement = "";
    String result = "";

    int quantityOpen = 0;
    int quantityClose = 0;

    String fileResult = (await rootBundle.loadString(
        'lib/src/services/graphql/${StringConverter.camelCaseToSnakeCase(path)}.graphql'));

    String stringType = type == RequestGraphQLType.query ? "query" : "mutation";
    bool firstLine = false;
    for (String line in fileResult.split("\n")) {
      if (result.isNotEmpty) break;

      RegExp regex = RegExp("$stringType $requestName" r'(?=[({])');
      if (regex.hasMatch(line)) {
        firstLine = true;
      }
      if (firstLine) {
        quantityOpen += line.split("{").length;
        quantityClose += line.split("}").length;
        if (quantityOpen == quantityClose) {
          lineIncrement += line;
          result = lineIncrement;
          break;
        }
        lineIncrement += line;
      }
    }

    return result.trim();
  }
}
