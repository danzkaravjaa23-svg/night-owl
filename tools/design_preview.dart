// Local visual review only: no production login or database connection.
// flutter run -d web-server --web-port 5601 -t tools/design_preview.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/theme/theme_provider.dart';
import 'package:night_owl_ub/core/widgets/mobile_frame.dart';
import 'package:night_owl_ub/core/widgets/theme_reveal.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/feed/providers/saved_provider.dart';
import 'package:night_owl_ub/features/feed/providers/stories_provider.dart';
import 'package:night_owl_ub/features/feed/screens/feed_screen.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/map_screen.dart';
import 'package:night_owl_ub/features/notifications/providers/notification_provider.dart';
import 'package:night_owl_ub/features/profile/screens/profile_screen.dart';
import 'package:night_owl_ub/features/dm/screens/dm_list_screen.dart';
import 'package:night_owl_ub/features/shell/main_shell.dart';
import 'package:night_owl_ub/features/search/screens/search_screen.dart';
import 'package:night_owl_ub/models/user_profile.dart';
import 'package:night_owl_ub/models/venue.dart';

final _posts = [
  for (var i = 0; i < 3; i++)
    {
      'id': 'preview-post-$i',
      'user_id': 'preview-user',
      'caption': i == 0
          ? 'Хотын гэрэл асахад үдэш эхэлнэ. #Улаанбаатар'
          : 'Өнөө оройн дурсамжийг энд үлдээе. #NightOwl',
      'media_url': 'assets/assets/images/tonight_city.png',
      'created_at':
          DateTime.now().subtract(Duration(hours: i + 1)).toIso8601String(),
      'likes_count': 24 + i * 7,
      'comments_count': 3 + i,
      'profiles': {'id': 'preview-user', 'username': 'nightowl.preview'},
    }
];

class _PreviewClient extends http.BaseClient {
  final bool messagesFail;
  _PreviewClient({this.messagesFail = false});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Only GET and named read RPCs are supported; mutations stay local/blocked.
    final path = request.url.path;
    final feedRead =
        request.method == 'POST' && path.endsWith('/rpc/get_feed_cursor');
    final messageRead =
        request.method == 'POST' && path.endsWith('/rpc/dm_conversations');
    if (request.method != 'GET' && !feedRead && !messageRead) {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 405,
          request: request);
    }
    if (messageRead && messagesFail) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'message': 'Жишээ ачааллын алдаа',
            'code': 'PREVIEW_UNAVAILABLE',
          }))),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request);
    }
    final Object body = path.endsWith('/posts') || feedRead ? _posts : [];
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'local-preview-only',
    debug: false,
    httpClient: _PreviewClient(
        messagesFail: Uri.base.queryParameters['messages'] == 'error'),
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
  );
  // A fictional in-memory session lets the real profile's account-change
  // guards run normally. It has no credentials accepted by a real server.
  final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400;
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': 'preview-user', 'exp': expires})}.cHJldmlldw';
  await Supabase.instance.client.auth.recoverSession(jsonEncode({
    'access_token': token,
    'refresh_token': 'local-preview-only',
    'token_type': 'bearer',
    'expires_in': 86400,
    'user': {
      'id': 'preview-user',
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-10-11T00:00:00Z',
    },
  }));
  runApp(ProviderScope(overrides: [
    themeModeProvider.overrideWith((_) => ThemeModeNotifier(
          readMode: () async => Uri.base.queryParameters['theme'] ?? 'dark',
          writeMode: (_) async => true,
        )),
    sessionUserIdProvider.overrideWithValue('preview-user'),
    currentProfileProvider.overrideWith((_) async => UserProfile(
          id: 'preview-user',
          username: 'nightowl.preview',
          name: 'Үдшийн тэмдэглэл',
          bio: 'Хотын гэрэл, хөгжмийн хэмнэл, шинэ дурсамжууд.',
          interests: ['Хөгжим', 'Хотын амьдрал'],
          postsCount: 3,
          followersCount: 128,
          followingCount: 64,
        )),
    storiesProvider.overrideWith((_) async => []),
    savedPostIdsProvider.overrideWith((_) async => {}),
    feedFollowingIdsProvider.overrideWith((_) async => {}),
    upcomingEventsProvider.overrideWith((_) async => []),
    unreadNotifCountProvider.overrideWithValue(0),
    venuesProvider.overrideWith((_) async => [
          Venue(
              id: 'preview-venue',
              name: 'Violet Lounge · Жишээ',
              type: 'lounge',
              district: 'Сүхбаатар',
              address: 'Дизайны туршилтын газрын карт',
              lat: 47.9185,
              lng: 106.917,
              communityEnabled: false,
              createdAt: DateTime(2026)),
          Venue(
              id: 'preview-cafe',
              name: 'After Hours · Жишээ',
              type: 'cafe',
              lat: 47.9204,
              lng: 106.920,
              communityEnabled: false,
              createdAt: DateTime(2026)),
        ]),
    venueCatalogStatusProvider.overrideWith((_) => const VenueCatalogStatus()),
  ], child: const _PreviewApp()));
}

class _PreviewApp extends ConsumerStatefulWidget {
  const _PreviewApp();
  @override
  ConsumerState<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends ConsumerState<_PreviewApp> {
  late final _router = GoRouter(initialLocation: '/feed', routes: [
    ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
      GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
      GoRoute(
          path: '/explore',
          builder: (_, __) => const MapScreen(embedded: true)),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/dm', builder: (_, __) => const DmListScreen()),
      for (final path in ['/reels', '/saved'])
        GoRoute(
            path: path,
            builder: (_, __) => const Scaffold(
                body: Center(child: Text('Дизайны урьдчилсан харагдац')))),
    ]),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(
        path: '/:section/:action',
        builder: (context, __) => Scaffold(
            appBar: AppBar(title: const Text('Дизайны туршилт')),
            body: const Center(
                child: Text('Энэ үйлдлийг үндсэн аппд ашиглана.')))),
  ]);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Night Owl · Design preview',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ref.watch(themeModeProvider),
        routerConfig: _router,
        builder: (context, child) => LayoutBuilder(
          builder: (context, constraints) {
            // Browser viewport emulation briefly reports a 1px surface.
            if (constraints.maxWidth < 160 || constraints.maxHeight < 80) {
              return const SizedBox.shrink();
            }
            return ThemeReveal(
                child: ColoredBox(
              color: AppColors.bgBase,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('ДИЗАЙНЫ ТУРШИЛТ · ЖИШЭЭ ӨГӨГДӨЛ',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary))),
                Expanded(
                    child: MobileFrame(
                        maxWidth: 390,
                        wideLayout: Uri.base.queryParameters['desktop'] == '1',
                        child: child!)),
              ]),
            ));
          },
        ),
      );
}
