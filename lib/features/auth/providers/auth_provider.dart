import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/user_profile.dart';

// ─── Current auth user ───
final authUserProvider = StreamProvider<User?>((ref) {
  return SupabaseService.authStream.map((state) => state.session?.user);
});

// ─── Current user profile ───
final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = SupabaseService.currentUser;
  if (user == null) return null;

  final data = await SupabaseService.client
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  return data != null ? UserProfile.fromJson(data) : null;
});

// ─── Auth state notifier ───
class AuthNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    SupabaseService.authStream.listen((state) async {
      final user = state.session?.user;
      if (user == null) {
        this.state = const AsyncValue.data(null);
        return;
      }
      try {
        final data = await SupabaseService.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        this.state = AsyncValue.data(
            data != null ? UserProfile.fromJson(data) : null);
      } catch (e, st) {
        this.state = AsyncValue.error(e, st);
      }
    });
  }

  Future<void> signOut() async {
    await SupabaseService.client.auth.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final user = SupabaseService.currentUser!;
    await SupabaseService.client
        .from('profiles')
        .update({...updates, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', user.id);
    // Refresh
    final data = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    state = AsyncValue.data(UserProfile.fromJson(data));
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>(
        (_) => AuthNotifier());
