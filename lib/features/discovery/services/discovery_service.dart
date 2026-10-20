import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';

typedef JsonRow = Map<String, dynamic>;

class SocialRelationship {
  final bool following, requested, isPrivate, canView, blocked;
  final String dmState;
  const SocialRelationship(
      {this.following = false,
      this.requested = false,
      this.isPrivate = true,
      this.canView = false,
      this.blocked = false,
      this.dmState = 'blocked'});
  factory SocialRelationship.fromJson(JsonRow row) => SocialRelationship(
      following: row['following'] == true,
      requested: row['requested'] == true,
      isPrivate: row['private'] == true,
      canView: row['can_view'] == true,
      blocked: row['blocked'] == true,
      dmState: row['dm_state'] as String? ?? 'blocked');
  bool get canSend => dmState == 'new' || dmState == 'accepted';
}

String discoveryError(Object error) {
  if (error is PostgrestException) {
    if (error.code == 'PGRST202' ||
        error.code == '42703' ||
        error.code == '42P01') {
      return 'Шинэ боломжийн серверийн шинэчлэлт хийгдээгүй байна.';
    }
    if (error.code == '42501') {
      return 'Энэ үйлдлийг хийх эрхгүй эсвэл нууцлалын тохиргоо хязгаарласан байна.';
    }
    if (error.code == '54000') {
      return 'Олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоорой.';
    }
    if (error.code == '22023' || error.code == '23514') {
      return 'Мэдээллээ бүрэн, зөв бөглөөд дахин оролдоорой.';
    }
  }
  return 'Холбогдож чадсангүй. Дахин оролдоорой.';
}

class DiscoveryService {
  final SupabaseClient client;
  DiscoveryService({SupabaseClient? client})
      : client = client ?? SupabaseService.client;
  String? get me => client.auth.currentUser?.id;
  Future<SocialRelationship> relationship(String id) async =>
      SocialRelationship.fromJson(Map<String, dynamic>.from(await client.rpc(
          'get_relationship',
          params: {'p_target': id}).timeout(const Duration(seconds: 15))));
  Future<String> follow(String id, bool value) async => await client
      .rpc('set_follow', params: {'p_target': id, 'p_follow': value}) as String;
  Future<void> respondFollow(String id, bool accept) =>
      client.rpc('respond_follow_request',
          params: {'p_requester': id, 'p_accept': accept});
  Future<void> respondMessage(String id, bool accept) =>
      client.rpc('respond_message_request',
          params: {'p_requester': id, 'p_accept': accept});
  Future<void> send(String id, String body,
          {String? note, String? story, String? venue}) =>
      client.rpc('send_direct_message', params: {
        'p_receiver': id,
        'p_body': body,
        'p_note': note,
        'p_story': story,
        'p_venue': venue
      });
  Future<List<JsonRow>> creators({String? interest, String query = ''}) async =>
      _rows(await client.rpc('discover_creators',
          params: {'p_interest': interest, 'p_query': query, 'p_limit': 20}));
  Future<JsonRow> privacy() async {
    if (me == null) throw StateError('Нэвтэрнэ үү');
    return await client
        .from('profiles')
        .select('is_private,dm_policy')
        .eq('id', me!)
        .single();
  }

  Future<void> setPrivacy(
      {required bool private, required String messages}) async {
    if (me == null) throw StateError('Нэвтэрнэ үү');
    await client
        .from('profiles')
        .update({'is_private': private, 'dm_policy': messages})
        .eq('id', me!)
        .select('id')
        .single();
  }

  Future<List<JsonRow>> requests() async {
    if (me == null) return [];
    return _rows(await client
        .from('follow_requests')
        .select(
            'requester_id,created_at,profiles!requester_id(id,username,avatar_url)')
        .eq('target_id', me!)
        .order('created_at'));
  }

  Future<List<JsonRow>> collections(String user) async => _rows(await client
      .from('place_collections')
      .select('*, collection_places(venue_ref,note,venue_catalog(*))')
      .eq('user_id', user)
      .order('created_at', ascending: false));
  Future<String> createCollection(String title, {bool public = true}) async {
    if (me == null) throw StateError('Нэвтэрнэ үү');
    final row = await client
        .from('place_collections')
        .insert({'user_id': me, 'title': title.trim(), 'is_public': public})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> addPlace(String collection, String venue,
          {String note = ''}) async =>
      client.from('collection_places').upsert(
          {'collection_id': collection, 'venue_ref': venue, 'note': note},
          onConflict: 'collection_id,venue_ref');
  Future<void> removePlace(String collection, String venue) async => client
      .from('collection_places')
      .delete()
      .eq('collection_id', collection)
      .eq('venue_ref', venue);
  Future<void> deleteCollection(String id) async =>
      client.from('place_collections').delete().eq('id', id);
  Future<void> collectionVisibility(String id, bool value) async => client
      .from('place_collections')
      .update({'is_public': value}).eq('id', id);
  Future<JsonRow?> venue(String ref) =>
      client.from('venue_catalog').select().eq('ref', ref).maybeSingle();
  Future<List<JsonRow>> venuePosts(String ref) async => _rows(await client
      .from('posts')
      .select(
          'id,user_id,caption,media_url,media_type,profiles!user_id(username,avatar_url)')
      .eq('venue_ref', ref)
      .order('created_at', ascending: false)
      .limit(30));
  Future<List<JsonRow>> catalog(
      {String query = '', bool reviewed = false}) async {
    var q = client.from('venue_catalog').select();
    if (query.trim().isNotEmpty) {
      q = q.ilike(
          'name', '%${query.trim().replaceAll(RegExp(r'[,()]'), ' ')}%');
    }
    if (reviewed) q = q.not('reviewed_at', 'is', null);
    return _rows(await q.order('name').limit(100));
  }

  Future<Set<String>> savedVenues() async {
    if (me == null) return {};
    return (await client
            .from('venue_saves')
            .select('venue_ref')
            .eq('user_id', me!))
        .map((r) => r['venue_ref'] as String)
        .toSet();
  }

  Future<void> saveVenue(String ref, bool value) async {
    if (me == null) throw StateError('Нэвтэрнэ үү');
    if (value) {
      await client.from('venue_saves').upsert({'user_id': me, 'venue_ref': ref},
          onConflict: 'user_id,venue_ref', ignoreDuplicates: true);
    } else {
      await client
          .from('venue_saves')
          .delete()
          .eq('user_id', me!)
          .eq('venue_ref', ref);
    }
  }

  Future<void> importSavedVenues(String owner, Set<String> refs) =>
      client.rpc('import_venue_saves',
          params: {'p_owner': owner, 'p_refs': refs.toList()});

  Future<void> activity(String event, {String target = ''}) async {
    if (me == null) return;
    try {
      await client.rpc('record_discovery_activity',
          params: {'p_event': event, 'p_target': target});
    } catch (_) {
      // Analytics must never prevent navigation or content use.
    }
  }

  Future<JsonRow> pilot() async =>
      Map<String, dynamic>.from(await client.rpc('get_pilot_overview'));
  Future<List<JsonRow>> pilotCandidates(String kind, String query) async =>
      _rows(await client.rpc('search_pilot_candidates',
          params: {'p_kind': kind, 'p_query': query}));
  Future<void> pilotEntry(String kind, String id, bool value) =>
      client.rpc('set_pilot_entry',
          params: {'p_kind': kind, 'p_id': id, 'p_enabled': value});
  Future<void> reviewVenue(String ref, JsonRow details) =>
      client.rpc('review_venue', params: {'p_ref': ref, 'p_details': details});
  static List<JsonRow> _rows(dynamic data) =>
      (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
}

final discoveryServiceProvider = Provider((ref) => DiscoveryService());
final socialVersionProvider = StateProvider<int>((ref) => 0);
final privacyProvider = FutureProvider<JsonRow>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(discoveryServiceProvider).privacy();
});
final followRequestsProvider = FutureProvider<List<JsonRow>>((ref) {
  final me = ref.watch(sessionUserIdProvider);
  ref.watch(socialVersionProvider);
  return me == null
      ? Future.value([])
      : ref.watch(discoveryServiceProvider).requests();
});
