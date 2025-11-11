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
    for (RegExpMatch match in fragmentMatches) {
      int fragmentOpen = 0;
      int fragmentClose = 0;
      StringBuffer fragmentBuffer = StringBuffer();
      bool fragmentFirstLine = false;
      Set<String> nestedFragments = <String>{};

      final List<String> lines = fileResult.split("\n");

      for (String line in lines) {
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
      }

      final String fragmentContent = fragmentBuffer.toString();
      final List<String> fragmentLines = fragmentContent.split("\n");
      RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
      for (String line in fragmentLines) {
        Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(line);
        for (RegExpMatch nestedMatch in matches) {
          if (nestedMatch.group(1) != null &&
              !addedFragments.contains(nestedMatch.group(1))) {
            nestedFragments.add(nestedMatch.group(1)!);
          }
        }
      }

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
    StringBuffer resultBuffer = StringBuffer();
    String fileResult = (await rootBundle.loadString(
        'lib/src/services/graphql/${StringConverter.camelCaseToSnakeCase(path)}/${StringConverter.camelCaseToSnakeCase(path)}.graphql'));

    final List<String> lines = fileResult.split("\n");

    int quantityOpen = 0;
    int quantityClose = 0;
    String stringType = type == RequestGraphQLType.query ? "query" : "mutation";
    bool firstLine = false;
    Set<String> fragments = <String>{};
    Set<String> addedFragments = <String>{};

    for (String line in lines) {
      RegExp regex = RegExp("$stringType $requestName\\s*" r'(?=[({])');
      if (regex.hasMatch(line)) {
        firstLine = true;
      }
      if (firstLine) {
        quantityOpen += line.split("{").length - 1;
        quantityClose += line.split("}").length - 1;
        lineIncrement.writeln(line);
        if (quantityOpen == quantityClose) {
          break;
        }
      }
    }

    final String queryContent = lineIncrement.toString();
    resultBuffer.write(queryContent);
    RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
    Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(queryContent);
    for (RegExpMatch match in matches) {
      if (match.group(1) != null) {
        fragments.add(match.group(1)!);
      }
    }
    for (String fragment in fragments) {
      String fragmentContent =
          extractFragment(fragment, fileResult, addedFragments);
      if (!addedFragments.contains(fragment) && fragmentContent.isNotEmpty) {
        resultBuffer.writeln(fragmentContent);
        addedFragments.add(fragment);
      }
    }

    return resultBuffer.toString().trim();
  }
}
