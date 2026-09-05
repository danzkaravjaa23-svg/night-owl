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
import '../../features/map/screens/explore_screen.dart';
import '../../features/post/screens/create_post_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/dm/screens/dm_list_screen.dart';
import '../../features/dm/screens/dm_thread_screen.dart';
import '../../features/dm/screens/group_thread_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/follow_list_screen.dart';
import '../../features/profile/screens/settings_screen.dart';
import '../../features/profile/screens/change_password_screen.dart';
import '../../features/profile/screens/business_screen.dart';
import '../../features/profile/screens/venue_edit_screen.dart';
import '../../features/map/screens/venue_reviews_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/feed/screens/saved_posts_screen.dart';
import '../../features/admin/screens/admin_reports_screen.dart';
import '../../features/admin/screens/admin_panel_screen.dart';
import '../../features/admin/screens/admin_users_screen.dart';
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
  static const explore         = '/explore';
  static const createPost      = '/post/create';
  static const notifications   = '/notifications';
  static const dmList          = '/dm';
  static const dmThread        = '/dm/:id';
  static const groupThread     = '/group/:id';
  static const profile         = '/profile';
  static const follows         = '/follows/:id';
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
  static const search          = '/search';
  static const saved           = '/saved';
  static const adminPanel      = '/admin';
  static const adminReports    = '/admin/reports';
  static const adminUsers      = '/admin/users';

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

// ─── Гөлгөр шилжилтүүд ───

/// Таб хоорондын шилжилт — зөөлөн fade + бага зэрэг томрох (Material fade-through)
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

/// Дэлгэрэнгүй дэлгэц — баруунаас гулсаж орох (iOS-маяг) + fade
CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, anim, secondary, child) {
        final curved = CurvedAnimation(
            parent: anim, curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

/// Үүсгэх дэлгэц — доороос гулсаж гарч ирнэ (sheet-маяг)
CustomTransitionPage<void> _sheetPage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
            parent: anim, curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

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
      GoRoute(path: AppRoutes.langSelect,
        pageBuilder: (_, s) => _fadePage(s, const LangSelectScreen())),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (_, state) {
          final slide = int.tryParse(state.uri.queryParameters['slide'] ?? '1') ?? 1;
          return _fadePage(state, OnboardingScreen(slide: slide));
        },
      ),
      GoRoute(path: AppRoutes.permLocation,
        builder: (_, __) => const PermissionScreen(kind: PermissionKind.location)),
      GoRoute(path: AppRoutes.permNotif,
        builder: (_, __) => const PermissionScreen(kind: PermissionKind.notification)),

      // ── Auth ──
      GoRoute(path: AppRoutes.authLanding,
        pageBuilder: (_, s) => _fadePage(s, const AuthLandingScreen())),
      GoRoute(path: AppRoutes.login,
        pageBuilder: (_, s) => _slidePage(s, const LoginScreen())),
      GoRoute(path: AppRoutes.register,
        pageBuilder: (_, s) => _slidePage(s, const RegisterScreen())),
      GoRoute(path: AppRoutes.setup,
        pageBuilder: (_, s) => _slidePage(s, const SetupScreen())),
      GoRoute(path: AppRoutes.forgotPassword,
        pageBuilder: (_, s) => _slidePage(s, const ForgotPasswordScreen())),

      // ── Main shell (bottom nav) ──
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.feed,
            pageBuilder: (_, s) => _fadePage(s, const FeedScreen())),
          GoRoute(path: AppRoutes.explore,
            pageBuilder: (_, s) => _fadePage(s, const ExploreScreen())),
          GoRoute(path: AppRoutes.notifications,
            pageBuilder: (_, s) => _fadePage(s, const NotificationsScreen())),
          GoRoute(path: AppRoutes.reels,
            pageBuilder: (_, s) => _fadePage(s, const ReelsScreen())),
          GoRoute(path: AppRoutes.profile,
            pageBuilder: (_, s) => _fadePage(s, const ProfileScreen())),
        ],
      ),

      // ── Full-screen overlays ──
      GoRoute(path: AppRoutes.map,
        // iframe (Leaflet) нь route transition-ий transform-ыг дагадаггүй тул
        // шилжилтгүй нээнэ — эс бөгөөс зураг байрлалаасаа гулсаж хар харагдана
        pageBuilder: (_, s) => NoTransitionPage(
            key: s.pageKey, child: const MapScreen())),
      GoRoute(path: AppRoutes.createPost,
        pageBuilder: (_, s) => _sheetPage(s, const CreatePostScreen())),
      GoRoute(path: AppRoutes.postDetail,
        pageBuilder: (_, s) => _slidePage(s,
          PostDetailScreen(postId: s.pathParameters['id'] ?? ''))),
      GoRoute(path: AppRoutes.creator,
        pageBuilder: (_, s) => _slidePage(s,
          CreatorScreen(creatorId: s.pathParameters['id'] ?? ''))),
      GoRoute(path: AppRoutes.qpay,
        pageBuilder: (_, s) => _sheetPage(s,
          QPayScreen(contentId: s.pathParameters['id'] ?? ''))),
      GoRoute(path: AppRoutes.dmList,
        pageBuilder: (_, s) => _slidePage(s, const DmListScreen())),
      GoRoute(path: AppRoutes.dmThread,
        pageBuilder: (_, s) => _slidePage(s, DmThreadScreen(
          threadId: s.pathParameters['id'] ?? '',
          replyNote: s.uri.queryParameters['note']))),
      GoRoute(path: AppRoutes.groupThread,
        pageBuilder: (_, s) => _slidePage(s, GroupThreadScreen(
          groupId: s.pathParameters['id'] ?? '',
          groupName: s.uri.queryParameters['name']))),
      GoRoute(path: AppRoutes.follows,
        pageBuilder: (_, s) => _slidePage(s, FollowListScreen(
          userId: s.pathParameters['id'] ?? '',
          showFollowers: s.uri.queryParameters['tab'] != 'following'))),
      GoRoute(path: AppRoutes.settings,
        pageBuilder: (_, s) => _slidePage(s, const SettingsScreen())),
      GoRoute(path: AppRoutes.changePassword,
        pageBuilder: (_, s) => _slidePage(s, const ChangePasswordScreen())),
      GoRoute(path: AppRoutes.business,
        pageBuilder: (_, s) => _slidePage(s, const BusinessScreen())),
      GoRoute(path: AppRoutes.affiliateUnlock,
        pageBuilder: (_, s) => _slidePage(s, const AffiliateScreen(unlockMode: true))),
      GoRoute(path: AppRoutes.affiliate,
        pageBuilder: (_, s) => _slidePage(s, const AffiliateScreen(unlockMode: false))),
      GoRoute(path: AppRoutes.goLive,
        pageBuilder: (_, s) => _sheetPage(s, const GoLiveScreen())),
      GoRoute(path: AppRoutes.liveView,
        // HTML5 video platform view — transition-гүй нээнэ
        pageBuilder: (_, s) => NoTransitionPage(key: s.pageKey,
          child: LiveViewerScreen(liveId: s.pathParameters['id'] ?? ''))),
      GoRoute(path: AppRoutes.createStory,
        pageBuilder: (_, s) => _sheetPage(s, const CreateStoryScreen())),
      GoRoute(path: AppRoutes.createReel,
        pageBuilder: (_, s) => _sheetPage(s, const CreateReelScreen())),
      GoRoute(path: AppRoutes.createEvent,
        pageBuilder: (_, s) => _sheetPage(s, const CreateEventScreen())),
      GoRoute(path: AppRoutes.venueEdit,
        pageBuilder: (_, s) => _slidePage(s, const VenueEditScreen())),
      GoRoute(path: AppRoutes.venueReviews,
        pageBuilder: (_, s) => _slidePage(s,
          VenueDetailScreen(venueId: s.pathParameters['id'] ?? ''))),
      GoRoute(path: AppRoutes.search,
        pageBuilder: (_, s) => _fadePage(s, const SearchScreen())),
      GoRoute(path: AppRoutes.saved,
        pageBuilder: (_, s) => _slidePage(s, const SavedPostsScreen())),
      GoRoute(path: AppRoutes.adminPanel,
        pageBuilder: (_, s) => _slidePage(s, const AdminPanelScreen())),
      GoRoute(path: AppRoutes.adminReports,
        pageBuilder: (_, s) => _slidePage(s, const AdminReportsScreen())),
      GoRoute(path: AppRoutes.adminUsers,
        pageBuilder: (_, s) => _slidePage(s, const AdminUsersScreen())),
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
