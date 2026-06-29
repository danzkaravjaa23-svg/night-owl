import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_preview/device_preview.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/feed/providers/feed_provider.dart';
import 'features/feed/providers/saved_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar — transparent (dark content shown over aurora)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Supabase
  await SupabaseService.initialize();

  // Утасны хүрээ дотор preview (зөвхөн debug; release-д унтарна).
  // Унтраах:  flutter run -d chrome --dart-define=DEVICE_PREVIEW=false
  const usePreview = !kReleaseMode &&
      bool.fromEnvironment('DEVICE_PREVIEW', defaultValue: true);

  runApp(
    DevicePreview(
      enabled: usePreview,
      builder: (_) => const ProviderScope(child: NightOwlApp()),
    ),
  );
}

class NightOwlApp extends ConsumerWidget {
  const NightOwlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Хаяг солигдоход (signOut→signIn өөр хэрэглэгч) хуучин хэрэглэгчийн
    // cache-ийг цэвэрлэнэ — өөр хаягийн дата харагдахаас сэргийлнэ.
    ref.listen(authUserProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        ref.invalidate(feedProvider);
        ref.invalidate(savedPostIdsProvider);
        // currentProfileProvider нь authUserProvider-ийг watch хийдэг тул
        // автоматаар шинэчлэгдэнэ.
      }
    });

    return MaterialApp.router(
      title: 'Night Owl UB',
      debugShowCheckedModeBanner: false,

      // device_preview — сонгосон утасны хэмжээ/locale-ийг апп-д тусгана
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,

      // Theme
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode, // System / Light / Dark — Settings → Appearance

      // Router
      routerConfig: router,
    );
  }
}
