import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

final ValueNotifier<Rect?> _none = ValueNotifier<Rect?>(null);

/// Web биш платформ (Android/iOS апп, тест) — хостингийн badge байхгүй,
/// үргэлж null.
ValueListenable<Rect?> get hostBadgeRect => _none;
