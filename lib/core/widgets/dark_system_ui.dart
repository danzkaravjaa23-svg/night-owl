import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Горимоос үл хамааран харанхуй дэлгэц — Android-ийн статус/навигацийн
/// мөрийн дүрсийг цагаан байлгана. Вэб дээр <meta theme-color>-г
/// өөрчлөхгүйн тулд юу ч хийхгүй.
class DarkSystemUi extends StatelessWidget {
  final Widget child;
  const DarkSystemUi({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}
