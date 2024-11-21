import 'package:flutter/services.dart';
import 'package:manager_api/requests/graphql_request.dart';
import 'package:manager_api/utils/string_converter.dart';

class GraphQLRead {
  GraphQLRead._();
  static String extractFragment(
      String fragmentName, String fileResult, Set<String> addedFragments) {
    RegExp fragmentRegex =
        RegExp(r'fragment\s+' + fragmentName + r'\s+on\s+\w+\s*\{');
    Iterable<RegExpMatch> fragmentMatches =
        fragmentRegex.allMatches(fileResult);
    for (var match in fragmentMatches) {
      int fragmentOpen = 0;
      int fragmentClose = 0;
      StringBuffer fragmentBuffer = StringBuffer();
      bool fragmentFirstLine = false;
      Set<String> nestedFragments = {};

      for (String line in fileResult.split("\n")) {
        if (fragmentFirstLine) {
          fragmentOpen += line.split("{").length - 1;
          fragmentClose += line.split("}").length - 1;
          fragmentBuffer.writeln(line);
          if (fragmentOpen == fragmentClose) {
            break;
          }
        } else if (line.contains(match.group(0)!)) {
          fragmentFirstLine = true;
          fragmentOpen += line.split("{").length - 1;
          fragmentClose += line.split("}").length - 1;
          fragmentBuffer.writeln(line);
        }

        // Check for nested fragment usage
        RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
        Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(line);
        for (var nestedMatch in matches) {
          if (nestedMatch.group(1) != null) {
            nestedFragments.add(nestedMatch.group(1)!);
          }
        }
      }

      // Recursively add nested fragments
      for (String nestedFragment in nestedFragments) {
        if (!addedFragments.contains(nestedFragment)) {
          String nestedFragmentContent =
              extractFragment(nestedFragment, fileResult, addedFragments);
          if (nestedFragmentContent.isNotEmpty) {
            fragmentBuffer.writeln(nestedFragmentContent);
            addedFragments.add(nestedFragment);
          }
        }
      }

      return fragmentBuffer.toString();
    }
    return "";
  }

  static Future<String> get({
    required String path,
    required RequestGraphQLType type,
    required String requestName,
  }) async {
    StringBuffer lineIncrement = StringBuffer();
    String result = "";
    String fileResult = (await rootBundle.loadString(
        'lib/src/services/graphql/${StringConverter.camelCaseToSnakeCase(path)}/${StringConverter.camelCaseToSnakeCase(path)}.graphql'));

    int quantityOpen = 0;
    int quantityClose = 0;
    String stringType = type == RequestGraphQLType.query ? "query" : "mutation";
    bool firstLine = false;
    Set<String> fragments = {};
    Set<String> addedFragments = {};

    for (String line in fileResult.split("\n")) {
      if (result.isNotEmpty) break;

      RegExp regex = RegExp("$stringType $requestName\\s*" r'(?=[({])');
      if (regex.hasMatch(line)) {
        firstLine = true;
      }
      if (firstLine) {
        quantityOpen += line.split("{").length - 1;
        quantityClose += line.split("}").length - 1;
        if (quantityOpen == quantityClose) {
          lineIncrement.writeln(line);
          result = lineIncrement.toString();
          break;
        }
        lineIncrement.writeln(line);

        // Check for fragment usage
        RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
        Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(line);
        for (var match in matches) {
          if (match.group(1) != null) {
            fragments.add(match.group(1)!);
          }
        }
      }
    }

    // Append fragments to the result
    for (String fragment in fragments) {
      String fragmentContent =
          extractFragment(fragment, fileResult, addedFragments);
      if (!addedFragments.contains(fragment) && fragmentContent.isNotEmpty) {
        result += "\n" + fragmentContent;
        addedFragments.add(fragment);
      }
    }

    return result.trim();
  }
}
