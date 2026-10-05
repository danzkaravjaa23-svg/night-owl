import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../utils/auth_callback.dart';
import '../utils/auth_callback_location.dart';

/// Нэвтрэх үйлчилгээний буцах холбоосын алдааг хэрэглэгчид тайлбарлана.
final authCallbackError = ValueNotifier<String?>(null);

/// Нууц үг сэргээх холбоосоор (token_hash) орж ирж, session амжилттай
/// баталгаажсан бол true — router шинэ нууц үгийн дэлгэц рүү аваачна.
bool pendingPasswordRecovery = false;

/// Нууц үг сая амжилттай солигдсон — нэвтрэх дэлгэц дээр мэдэгдэл харуулна.
bool passwordJustReset = false;

/// Supabase client singleton
class SupabaseService {
  SupabaseService._();
  static Stream<AuthState>? _authStream;
  static Object? _lastAuthStreamError;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
      // Exchange a web callback once here. Native deep links remain handled
      // by the SDK while the app is running or resumed from the browser.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: !kIsWeb,
      ),
    );

    if (!kIsWeb) return;
    final uri = Uri.base;
    var consumedCallback = false;
    // ── Нууц үг сэргээх холбоос (token_hash) ──
    // Имэйлийн template: {{ .SiteURL }}/?token_hash=…&type=recovery
    // verifyOTP нь ямар ч төхөөрөмж/browser дээр ажиллана (PKCE verifier
    // шаардахгүй) — тиймээс утасны Gmail-ээс дарсан ч ажиллана.
    {
      final q = uri.queryParameters;
      final th = q['token_hash'];
      if (th != null && th.isNotEmpty && q['type'] == 'recovery') {
        consumedCallback = true;
        try {
          await Supabase.instance.client.auth
              .verifyOTP(tokenHash: th, type: OtpType.recovery);
          pendingPasswordRecovery = true;
        } catch (_) {
          authCallbackError.value =
              'Сэргээх холбоос хүчингүй эсвэл хугацаа нь дууссан байна. '
              'Нууц үг сэргээхийг дахин хүсээрэй.';
        }
      }
    }

    if (hasOAuthCallback(uri)) {
      consumedCallback = true;
      try {
        final response = await Supabase.instance.client.auth.getSessionFromUrl(uri);
        if (response.redirectType == AuthChangeEvent.passwordRecovery.name) {
          pendingPasswordRecovery = true;
        }
      } on AuthException catch (error) {
        authCallbackError.value = oauthCallbackErrorMessage(
          uri.queryParameters['error'] ?? error.code,
        );
      } catch (_) {
        authCallbackError.value = oauthCallbackErrorMessage(null);
      }
    }

    if (consumedCallback) {
      // Do not exchange a consumed code again after a refresh, or leave
      // recovery/login credentials in browser history.
      try {
        replaceAuthCallbackLocation(uri);
      } catch (_) {
        debugPrint('Auth callback URL could not be cleared');
      }
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;

  // Native OAuth failures are emitted as stream errors by the SDK. Handle
  // them once, without discarding a valid session or exposing raw payloads.
  static Stream<AuthState> get authStream => _authStream ??=
      client.auth.onAuthStateChange.handleError((Object error) {
        if (identical(error, _lastAuthStreamError)) return;
        _lastAuthStreamError = error;
        authCallbackError.value = oauthCallbackErrorMessage(
          error is AuthException ? error.code : null,
        );
      });
}

/// Supabase table names
abstract class SupabaseTables {
  static const profiles = 'profiles';
  static const venues = 'venues';
  static const posts = 'posts';
  static const stories = 'stories';
  static const checkins = 'checkins';
  static const events = 'events';
  static const follows = 'follows';
  static const likes = 'likes';
  static const comments = 'comments';
  static const messages = 'messages';
  static const threads = 'threads';
  static const notifications = 'notifications';
}

/// Supabase storage buckets
abstract class SupabaseBuckets {
  static const avatars = 'avatars';
  static const posts = 'posts';
  static const stories = 'stories';
  static const venues = 'venues';
}
