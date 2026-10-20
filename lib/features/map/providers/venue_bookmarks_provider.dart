import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';

/// Guest saves stay local; signed-in saves sync to this account only.
class VenueBookmarksNotifier extends StateNotifier<AsyncValue<Set<String>>> {
  final String? userId;
  final DiscoveryService? backend;
  late final Future<void> ready;
  bool _saving = false;
  VenueBookmarksNotifier(this.userId, {this.backend})
      : super(const AsyncValue.loading()) {
    ready = _load();
  }
  String get storageKey => 'venue_bookmarks.${userId ?? 'guest'}';
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var ids = (prefs.getStringList(storageKey) ?? <String>[]).toSet();
      if (backend != null) {
        if (backend!.me != userId) throw StateError('Account changed');
        var remote = await backend!.savedVenues();
        if (!mounted || backend!.me != userId) return;
        if (prefs.getBool('$storageKey.synced') != true) {
          final missing = ids.difference(remote);
          if (missing.isNotEmpty) {
            await backend!.importSavedVenues(userId!, missing);
            if (!mounted || backend!.me != userId) return;
            remote = await backend!.savedVenues();
            if (!mounted || backend!.me != userId) return;
          }
          if (!await prefs.setBool('$storageKey.synced', true)) {
            throw StateError('Bookmark import state was not saved');
          }
        }
        ids = remote;
        await prefs.setStringList(storageKey, ids.toList()..sort());
        if (!mounted || backend!.me != userId) return;
      }
      if (mounted) state = AsyncValue.data(ids);
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> toggle(String venueId) async {
    await ready;
    if (!mounted) return;
    if (!state.hasValue) {
      await _load();
      if (!mounted) return;
      if (!state.hasValue) {
        throw StateError('Stored venue bookmarks could not be read');
      }
    }
    if (_saving) throw StateError('A venue save is already in progress');
    _saving = true;
    try {
      final next = {...?state.valueOrNull};
      if (!next.remove(venueId)) next.add(venueId);
      if (backend != null) {
        if (backend!.me != userId) throw StateError('Account changed');
        await backend!.saveVenue(venueId, next.contains(venueId));
        if (!mounted || backend!.me != userId) return;
        state = AsyncValue.data(next);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(storageKey, next.toList()..sort());
        } catch (_) {
          // The server is authoritative; a cache failure must not undo a save.
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(storageKey, next.toList()..sort())) {
        throw StateError('Venue bookmark was not saved');
      }
      if (mounted) state = AsyncValue.data(next);
    } finally {
      _saving = false;
    }
  }
}

final venueBookmarksProvider = StateNotifierProvider.autoDispose<
    VenueBookmarksNotifier, AsyncValue<Set<String>>>((ref) {
  final id = ref.watch(sessionUserIdProvider);
  DiscoveryService? backend;
  try {
    if (id != null && SupabaseService.currentUser?.id == id) {
      backend = ref.watch(discoveryServiceProvider);
    }
  } catch (_) {}
  return VenueBookmarksNotifier(id, backend: backend);
});
