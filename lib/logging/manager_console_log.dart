import 'dart:ui' show Color;

import 'package:ansicolor/ansicolor.dart';
import 'package:flutter/foundation.dart';

abstract final class ManagerConsoleLog {
  ManagerConsoleLog._();

  static const Color graphqlBadge = Color(0xFF7E57C2);

  static const Color restBadge = Color(0xFF00897B);

  static const Color socketBadge = Color(0xFF1E88E5);

  static const Color uploadBadge = Color(0xFF6D4C41);

  static const int _badgeWidth = 7;

  static void emit({
    required String title,
    required String message,
    required Color accent,
    Color? badge,
  }) {
    if (kReleaseMode) {
      return;
    }

    ansiColorDisabled = false;

    final Color badgeColor = badge ?? _badgeFor(title);
    final AnsiPen badgePen = AnsiPen()
      ..rgb(r: badgeColor.r, g: badgeColor.g, b: badgeColor.b, bg: true);

    if (badgeColor.computeLuminance() > 0.45) {
      badgePen.black();
    } else {
      badgePen.white(bold: true);
    }

    final AnsiPen messagePen = AnsiPen()
      ..rgb(r: accent.r, g: accent.g, b: accent.b);

    final String label = title.length >= _badgeWidth
        ? title
        : title.padRight(_badgeWidth);

    debugPrint(
      '${badgePen(' $label ')} ${messagePen(message)}',
      wrapWidth: 20000,
    );
  }

  static Color _badgeFor(String title) {
    if (title.startsWith('WS')) {
      return socketBadge;
    }

    if (title.startsWith('REST')) {
      return restBadge;
    }

    if (title.startsWith('Upload')) {
      return uploadBadge;
    }

    return graphqlBadge;
  }
}
