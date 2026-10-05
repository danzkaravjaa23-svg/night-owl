import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_preview/device_preview.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/widgets/mobile_frame.dart';
import 'core/widgets/theme_reveal.dart';
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

  // Утасны хүрээ дотор preview (зөвхөн веб debug; утас болон release-д унтарна).
  // Унтраах:  flutter run -d chrome --dart-define=DEVICE_PREVIEW=false
  const usePreview = kIsWeb &&
      !kReleaseMode &&
      bool.fromEnvironment('DEVICE_PREVIEW', defaultValue: true);

  runApp(
    DevicePreview(
      enabled: usePreview,
      builder: (_) => const ProviderScope(child: NightOwlApp()),
    ),
  );
}

class NightOwlApp extends ConsumerStatefulWidget {
  const NightOwlApp({super.key});

  @override
  ConsumerState<NightOwlApp> createState() => _NightOwlAppState();
}

class _NightOwlAppState extends ConsumerState<NightOwlApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    authCallbackError.addListener(_showAuthCallbackError);
    _showAuthCallbackError();
  }

  void _showAuthCallbackError() {
    final message = authCallbackError.value;
    if (message == null) return;
    authCallbackError.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('Нэвтрэлт: $message'),
      ));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    authCallbackError.removeListener(_showAuthCallbackError);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      scaffoldMessengerKey: _messengerKey,

      // device_preview — сонгосон утасны хэмжээ/locale-ийг апп-д тусгана
      locale: DevicePreview.locale(context),
      // Веб/desktop дээр утасны өргөнөөр голлуулна (MobileFrame).
      // ThemeReveal гадна талд — горим солиход хажуугийн зай ч хамт тэлнэ.
      builder: (context, child) {
        final tree = ListenableBuilder(
          listenable: router.routeInformationProvider,
          builder: (context, _) => ThemeReveal(
              child: MobileFrame(
                  wideLayout: {
                    AppRoutes.feed,
                    AppRoutes.explore,
                    AppRoutes.profile,
                    AppRoutes.map,
                    AppRoutes.reels,
                    AppRoutes.dmList
                  }.contains(router.routeInformationProvider.value.uri.path),
                  child: DevicePreview.appBuilder(context, child))),
        );
        // Веб дээр statusBarColor нь <meta theme-color>-г солидог тул оролцуулахгүй
        if (kIsWeb) return tree;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: tree,
        );
      },

      // Theme
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode, // System / Light / Dark — хиртэлтийн toggle
      // Theme-ийн өөрийн 200мс шилжилтийг унтраана: өнгөний токенууд (static
      // getter) шууд солигддог тул хоёр өөр хурдтай шилжилт зөрөх байсан.
      // Шилжилтийг ThemeReveal-ийн тойрог дэлгэрэлт хийнэ.
      themeAnimationDuration: Duration.zero,

      // Router
      routerConfig: router,
    );
  }
}
