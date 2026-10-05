import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/user_profile.dart';

// ─── Current auth user ───
final authUserProvider = StreamProvider<User?>((ref) {
  return SupabaseService.authStream.map((state) => state.session?.user);
});

// The id is stable during token refresh, and null after sign-out.
final sessionUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authUserProvider);
  return session.hasValue ? session.valueOrNull?.id : SupabaseService.currentUser?.id;
});

// ─── Current user profile ───
// authUserProvider-ийг watch хийснээр хаяг солиход (signOut→signIn) автоматаар
// дахин уншиж, хуучин хэрэглэгчийн профайл cache-д үлдэхээс сэргийлнэ.
final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return null;

  final data = await SupabaseService.client
      .from('profiles')
      .select()
      .eq('id', userId)
      .maybeSingle();

  return data != null ? UserProfile.fromJson(data) : null;
});

// ─── Auth state notifier ───
class AuthNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  StreamSubscription<AuthState>? _sub;
  int _request = 0;

  void _init() {
    _sub = SupabaseService.authStream.listen((state) async {
      final request = ++_request;
      final user = state.session?.user;
      if (user == null) {
        if (!mounted || request != _request) return;
        this.state = const AsyncValue.data(null);
        return;
      }
      try {
        final data = await SupabaseService.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        // await-ийн дараа notifier dispose хийгдсэн байж болно
        if (!mounted || request != _request) return;
        this.state = AsyncValue.data(
            data != null ? UserProfile.fromJson(data) : null);
      } catch (e, st) {
        if (!mounted || request != _request) return;
        this.state = AsyncValue.error(e, st);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> signOut() async {
    await SupabaseService.client.auth.signOut();
    if (!mounted) return;
    state = const AsyncValue.data(null);
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    // Session дууссан үед null байж болно — crash хийхгүй
    final user = SupabaseService.currentUser;
    if (user == null) throw StateError('Нэвтэрнэ үү');
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
    if (!mounted) return;
    state = AsyncValue.data(UserProfile.fromJson(data));
  }
}

/// Хэрэглэгч пост/reel нийтэлсэн бүрт нэмэгдэнэ — профайлын grid, тоо
/// энийг watch хийж өөрсдийгөө шинэчилнэ (ProfileScreen доор нь mounted хэвээр).
final postsVersionProvider = StateProvider<int>((ref) => 0);

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>(
        (_) => AuthNotifier());
