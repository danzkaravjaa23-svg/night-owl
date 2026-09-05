import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

/// Google-ээс буцаж ирэхэд session солих алдаа гарсан бол энд хадгална.
/// (Нэвтрэх дэлгэц дээр харуулж, шалтгааныг нуухгүй.)
String? lastAuthCallbackError;

/// Supabase client singleton
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );

    // ── OAuth callback fallback ──
    // supabase_flutter өөрөө URL-аас session солихыг оролддог ч web дээр
    // (PKCE verifier, timing) бүтэлгүйтэх тохиолдол бий. Тэр үед session
    // үүсэхгүй тул хэрэглэгч буцаад нэвтрэх хуудсанд гарч ирдэг.
    // Session алга + URL-д code/token байвал өөрсдөө дахин оролдоно.
    if (kIsWeb && Supabase.instance.client.auth.currentSession == null) {
      final uri = Uri.base;
      final hasCallback = uri.queryParameters.containsKey('code') ||
          uri.fragment.contains('access_token') ||
          uri.queryParameters.containsKey('error') ||
          uri.fragment.contains('error_description');
      if (hasCallback) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
        } catch (e) {
          lastAuthCallbackError = e.toString();
          debugPrint('OAuth callback exchange failed: $e');
        }
      }
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;

  static Stream<AuthState> get authStream => client.auth.onAuthStateChange;
}

/// Supabase table names
abstract class SupabaseTables {
  static const profiles   = 'profiles';
  static const venues     = 'venues';
  static const posts      = 'posts';
  static const stories    = 'stories';
  static const checkins   = 'checkins';
  static const events     = 'events';
  static const follows    = 'follows';
  static const likes      = 'likes';
  static const comments   = 'comments';
  static const messages   = 'messages';
  static const threads    = 'threads';
  static const notifications = 'notifications';
}

/// Supabase storage buckets
abstract class SupabaseBuckets {
  static const avatars  = 'avatars';
  static const posts    = 'posts';
  static const stories  = 'stories';
  static const venues   = 'venues';
}
