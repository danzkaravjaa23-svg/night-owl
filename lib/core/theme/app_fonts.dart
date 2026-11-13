import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// The fonts used by the app and story editor ship with every build.
///
/// Inter is a pubspec font family (five real weights) that the engine
/// registers at launch. google_fonts only serves JetBrains Mono and the story
/// fonts, from the same bundled assets and never from the network.
abstract final class AppFonts {
  static bool _licensesRegistered = false;

  /// Call after the Flutter binding is initialized, before creating any styles.
  static void configure() {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_licensesRegistered) return;
    _licensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      for (final family in const [
        'Inter',
        'JetBrainsMono',
        'Manrope',
        'PlayfairDisplay',
        'Pacifico',
        'BebasNeue',
      ]) {
        final license =
            await rootBundle.loadString('assets/fonts/$family-OFL.txt');
        yield LicenseEntryWithLineBreaks([family], license);
      }
    });
  }
}
