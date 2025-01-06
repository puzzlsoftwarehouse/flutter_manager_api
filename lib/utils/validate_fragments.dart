import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ValidateFragments {
  static Future<String?> validateAllGraphQLFiles() async {
    final directory = Directory('lib/src/services/graphql');
    final files = directory
        .listSync(recursive: true)
        .where((file) => file.path.endsWith('.graphql'));

    for (var file in files) {
      final path = file.path.replaceAll('\\', '/');
      final String? fragmentNotFound = await _validateFragments(path);
      if (fragmentNotFound != null) {
        debugPrint('File: $path has not the fragment $fragmentNotFound');
        return 'File: $path has not the fragment $fragmentNotFound';
      }
    }
    return null;
  }

  static Future<String?> _validateFragments(String path) async {
    String fileResult = await rootBundle.loadString(path);
    Set<String> fragments = _extractFragments(fileResult);
    for (String fragment in fragments) {
      if (!_doesFragmentExist(fragment, fileResult)) {
        return fragment;
      }
    }
    return null;
  }

  static Set<String> _extractFragments(String fileResult) {
    Set<String> fragments = {};
    RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
    Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(fileResult);
    for (var match in matches) {
      if (match.group(1) != null) {
        fragments.add(match.group(1)!);
      }
    }
    return fragments;
  }

  static bool _doesFragmentExist(String fragmentName, String fileResult) {
    RegExp fragmentRegex =
        RegExp(r'fragment\s+' + fragmentName + r'\s+on\s+\w+\s*\{');
    return fragmentRegex.hasMatch(fileResult);
  }
}
