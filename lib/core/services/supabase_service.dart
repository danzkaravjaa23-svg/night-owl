import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

/// Supabase client singleton
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
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
