import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/onboarding/screens/splash_screen.dart';
import '../../features/onboarding/screens/lang_select_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/permission_screen.dart';
import '../../features/auth/screens/auth_landing_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/setup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/feed/screens/feed_screen.dart';
import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/feed/screens/creator_screen.dart';
import '../../features/feed/screens/qpay_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/map/screens/bar_screen.dart';
import '../../features/post/screens/create_post_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/dm/screens/dm_list_screen.dart';
import '../../features/dm/screens/dm_thread_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/settings_screen.dart';
import '../../features/profile/screens/change_password_screen.dart';
import '../../features/profile/screens/business_screen.dart';
import '../../features/profile/screens/venue_edit_screen.dart';
import '../../features/map/screens/venue_reviews_screen.dart';
import '../../features/profile/screens/affiliate_screen.dart';
import '../../features/live/screens/go_live_screen.dart';
import '../../features/live/screens/live_viewer_screen.dart';
import '../../features/feed/screens/create_story_screen.dart';
import '../../features/feed/screens/reels_screen.dart';
import '../../features/feed/screens/create_reel_screen.dart';
import '../../features/events/screens/create_event_screen.dart';

// ─── Route names ───
abstract class AppRoutes {
  static const splash          = '/';
  static const langSelect      = '/lang-select';
  static const onboarding      = '/onboarding';
  static const permLocation    = '/perm/location';
  static const permNotif       = '/perm/notification';
  static const authLanding     = '/auth';
  static const login           = '/auth/login';
  static const register        = '/auth/register';
  static const setup           = '/auth/setup';
  static const forgotPassword  = '/auth/forgot-password';
  static const feed            = '/feed';
  static const postDetail      = '/post/:id';
  static const creator         = '/creator/:id';
  static const qpay            = '/qpay/:id';
  static const map             = '/map';
  static const bar             = '/bar/:id';
  static const createPost      = '/post/create';
  static const notifications   = '/notifications';
  static const dmList          = '/dm';
  static const dmThread        = '/dm/:id';
  static const profile         = '/profile';
  static const settings        = '/settings';
  static const changePassword  = '/settings/password';
  static const business        = '/business';
  static const affiliateUnlock = '/affiliate/unlock';
  static const affiliate       = '/affiliate';
  static const goLive          = '/live/go';
  static const liveView        = '/live/view/:id';
  static const createStory     = '/story/create';
  static const reels           = '/reels';
  static const createReel      = '/reels/create';
  static const createEvent     = '/event/create';
  static const venueEdit       = '/venue/edit';
  static const venueReviews    = '/venue/reviews/:id';

  // Нэвтрэлт шаардахгүй routes
  static const _publicRoutes = {
    splash, langSelect, onboarding, permLocation, permNotif,
    authLanding, login, register, setup, forgotPassword,
  };

  static bool isPublic(String location) =>
      _publicRoutes.any((r) => location.startsWith(r.split(':')[0]));
}

final _rootKey  = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,

    // ─── Auth redirect ───
    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final isLoggedIn = user != null;
      final loc = state.uri.toString();

      if (!isLoggedIn && !AppRoutes.isPublic(loc)) {
        return AppRoutes.authLanding;
      }
      return null;
    },

    refreshListenable: _SupabaseAuthListenable(),

    routes: [
      // ── Onboarding ──
      GoRoute(path: AppRoutes.splash,       builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.langSelect,   builder: (_, __) => const LangSelectScreen()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, state) {
          final slide = int.tryParse(state.uri.queryParameters['slide'] ?? '1') ?? 1;
          return OnboardingScreen(slide: slide);
        },
      ),
      GoRoute(path: AppRoutes.permLocation,
        builder: (_, __) => const PermissionScreen(kind: PermissionKind.location)),
      GoRoute(path: AppRoutes.permNotif,
        builder: (_, __) => const PermissionScreen(kind: PermissionKind.notification)),

      // ── Auth ──
      GoRoute(path: AppRoutes.authLanding,   builder: (_, __) => const AuthLandingScreen()),
      GoRoute(path: AppRoutes.login,         builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.register,      builder: (_, __) => const RegisterScreen()),
      GoRoute(path: AppRoutes.setup,         builder: (_, __) => const SetupScreen()),
      GoRoute(path: AppRoutes.forgotPassword,builder: (_, __) => const ForgotPasswordScreen()),

      // ── Main shell (bottom nav) ──
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.feed,          builder: (_, __) => const FeedScreen()),
          GoRoute(path: AppRoutes.map,           builder: (_, __) => const MapScreen()),
          GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: AppRoutes.reels,         builder: (_, __) => const ReelsScreen()),
          GoRoute(path: AppRoutes.profile,       builder: (_, __) => const ProfileScreen()),
        ],
      ),

      // ── Full-screen overlays ──
      GoRoute(path: AppRoutes.createPost,   builder: (_, __) => const CreatePostScreen()),
      GoRoute(path: AppRoutes.postDetail,
        builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.creator,
        builder: (_, s) => CreatorScreen(creatorId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.qpay,
        builder: (_, s) => QPayScreen(contentId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.bar,
        builder: (_, s) => BarScreen(venueId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.dmList,       builder: (_, __) => const DmListScreen()),
      GoRoute(path: AppRoutes.dmThread,
        builder: (_, s) => DmThreadScreen(threadId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.settings,     builder: (_, __) => const SettingsScreen()),
      GoRoute(path: AppRoutes.changePassword,builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: AppRoutes.business,     builder: (_, __) => const BusinessScreen()),
      GoRoute(path: AppRoutes.affiliateUnlock,
        builder: (_, __) => const AffiliateScreen(unlockMode: true)),
      GoRoute(path: AppRoutes.affiliate,
        builder: (_, __) => const AffiliateScreen(unlockMode: false)),
      GoRoute(path: AppRoutes.goLive,
        builder: (_, __) => const GoLiveScreen()),
      GoRoute(path: AppRoutes.liveView,
        builder: (_, s) => LiveViewerScreen(liveId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.createStory,
        builder: (_, __) => const CreateStoryScreen()),
      GoRoute(path: AppRoutes.createReel,
        builder: (_, __) => const CreateReelScreen()),
      GoRoute(path: AppRoutes.createEvent,
        builder: (_, __) => const CreateEventScreen()),
      GoRoute(path: AppRoutes.venueEdit,
        builder: (_, __) => const VenueEditScreen()),
      GoRoute(path: AppRoutes.venueReviews,
        builder: (_, s) => VenueDetailScreen(venueId: s.pathParameters['id'] ?? '')),
    ],

    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});

/// Supabase auth state → GoRouter refresh
class _SupabaseAuthListenable extends ChangeNotifier {
  _SupabaseAuthListenable() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
}
