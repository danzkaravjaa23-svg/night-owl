import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/utils/validators.dart';
import '../../auth/providers/auth_provider.dart';
import '../../post/services/content_publication.dart';

class EventItem {
  final String id;
  final String moderationStatus;
  final String? organizerId;
  final String title;
  final String? description;
  final String? coverUrl;
  final DateTime startsAt;
  final int price;
  final String? venueName;
  final String? organizerName;
  final int attendeeCount; // бодит RSVP тоо (events.attendee_count)
  const EventItem({
    required this.id,
    this.moderationStatus = 'approved',
    this.organizerId,
    required this.title,
    this.description,
    this.coverUrl,
    required this.startsAt,
    this.price = 0,
    this.venueName,
    this.organizerName,
    this.attendeeCount = 0,
  });
}

final eventServiceProvider = Provider<EventService>((ref) => EventService());

/// Explicit UTC avoids interpreting the device's wall clock as backend UTC.
String upcomingSince(DateTime now) =>
    now.subtract(const Duration(hours: 3)).toUtc().toIso8601String();

final upcomingEventsProvider = FutureProvider<List<EventItem>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(eventServiceProvider).loadUpcoming();
});

typedef EventRsvp = ({int going, int interested, String? mine});

final eventRsvpProvider =
    FutureProvider.autoDispose.family<EventRsvp, String>((ref, eventId) {
  final owner = ref.watch(sessionUserIdProvider);
  final service = ref.watch(eventServiceProvider);
  final session = owner == null ? null : service.captureSession();
  if (session != null) ref.onDispose(session.close);
  return service.loadRsvp(eventId, session: session);
});

/// Validated, immutable form snapshot. Retrying keeps the original ID/payload.
Map<String, dynamic> eventDraft({
  required String id,
  required String ownerId,
  required String title,
  required String description,
  required String? venueId,
  required DateTime? startsAt,
  required String price,
  required DateTime now,
}) {
  if (title.trim().isEmpty || title.trim().length > 120) {
    throw const PublicationFailure(
        'Эвентийн нэрийг 1–120 тэмдэгтээр оруулна уу');
  }
  if (description.trim().length > 5000) {
    throw const PublicationFailure('Тайлбар 5000 тэмдэгтээс хэтрэхгүй байна');
  }
  if (venueId == null || venueId.isEmpty) {
    throw const PublicationFailure('Эвент зохиох өөрийн газраа сонгоно уу');
  }
  if (startsAt == null || !startsAt.isAfter(now)) {
    throw const PublicationFailure(
        'Эвент эхлэх огноо, цаг ирээдүйд байх ёстой');
  }
  final priceError = Validators.admissionPrice(price);
  if (priceError != null) throw PublicationFailure(priceError);
  return Map.unmodifiable({
    'id': id,
    'organizer_id': ownerId,
    'venue_id': venueId,
    'title': title.trim(),
    'description': description.trim().isEmpty ? null : description.trim(),
    'starts_at': startsAt.toUtc().toIso8601String(),
    'price': int.tryParse(price.trim()) ?? 0,
  });
}

class EventService extends ContentPublicationService {
  final http.Client? _eventHttp;
  EventService({super.client, super.httpClient, super.requestTimeout})
      : _eventHttp = httpClient;

  Stream<void> get sessionChanges => client.auth.onAuthStateChange.map((_) {});

  Map<String, String> _eventHeaders(PublicationSession? session) {
    final headers = Map<String, String>.from(client.auth.headers)
      ..removeWhere((key, _) =>
          key.toLowerCase() == 'authorization' ||
          key.toLowerCase() == 'content-type');
    final key = headers.entries
        .where((e) => e.key.toLowerCase() == 'apikey')
        .first
        .value;
    return headers
      ..addAll({
        'Authorization': 'Bearer ${session?.token ?? key}',
        'Content-Type': 'application/json',
      });
  }

  void _checkReader(PublicationSession? session) {
    if (session != null) {
      session.check();
    } else if (client.auth.currentUser != null) {
      throw const PublicationFailure(
          'Нэвтрэх хаяг өөрчлөгдлөө. Дахин ачаална уу.');
    }
  }

  Future<List<EventItem>> loadUpcoming() async {
    final now = upcomingSince(DateTime.now());
    final data = await client
        .from('events')
        .select(
            'id, title, description, cover_url, starts_at, price, venue_id, organizer_id, attendee_count, moderation_status')
        .gte('starts_at', now)
        .order('starts_at', ascending: true)
        .limit(30);
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [];

    final venueIds =
        rows.map((r) => r['venue_id']).whereType<String>().toSet().toList();
    final orgIds =
        rows.map((r) => r['organizer_id']).whereType<String>().toSet().toList();

    Map<String, String> vmap = {};
    Map<String, String> omap = {};
    if (venueIds.isNotEmpty) {
      final vs = await client
          .from('venues')
          .select('id, name')
          .inFilter('id', venueIds);
      vmap = {
        for (final v in (vs as List).cast<Map<String, dynamic>>())
          v['id'] as String: v['name'] as String
      };
    }
    if (orgIds.isNotEmpty) {
      final os = await client
          .from('profiles')
          .select('id, username')
          .inFilter('id', orgIds);
      omap = {
        for (final o in (os as List).cast<Map<String, dynamic>>())
          o['id'] as String: o['username'] as String? ?? ''
      };
    }

    return rows
        .map((r) => EventItem(
              id: r['id'] as String,
              moderationStatus: r['moderation_status'] as String? ?? 'approved',
              organizerId: r['organizer_id'] as String?,
              title: r['title'] as String? ?? 'Event',
              description: r['description'] as String?,
              coverUrl: r['cover_url'] as String?,
              startsAt: DateTime.parse(r['starts_at'] as String),
              price: (r['price'] as num?)?.toInt() ?? 0,
              venueName: r['venue_id'] != null ? vmap[r['venue_id']] : null,
              organizerName:
                  r['organizer_id'] != null ? omap[r['organizer_id']] : null,
              attendeeCount: (r['attendee_count'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<List<Map<String, dynamic>>> ownedVenues(
      PublicationSession session, String query) async {
    session.check();
    final connection = _eventHttp ?? http.Client();
    try {
      final response = await connection
          .get(
            Uri.parse('${client.rest.url}/venues').replace(queryParameters: {
              'select': 'id,name,district',
              'owner_id': 'eq.${session.ownerId}',
              if (query.trim().isNotEmpty) 'name': 'ilike.*${query.trim()}*',
              'order': 'name.asc',
              'limit': '30',
            }),
            headers: _eventHeaders(session),
          )
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode != 200) throw const FormatException();
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Газруудыг ачаалж чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (_eventHttp == null) connection.close();
    }
  }

  Future<void> publishEvent(
      PublicationSession session, Map<String, dynamic> row) async {
    session.check();
    if (row['organizer_id'] != session.ownerId || row['id'] is! String) {
      throw const PublicationFailure('Нийтлэх мэдээлэл буруу байна.');
    }
    final connection = _eventHttp ?? http.Client();
    try {
      final endpoint = Uri.parse('${client.rest.url}/events');
      final response = await connection
          .post(
            endpoint,
            headers: _eventHeaders(session)..['Prefer'] = 'return=minimal',
            body: jsonEncode(row),
          )
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = jsonDecode(response.body);
        if (response.statusCode != 409 ||
            error is! Map ||
            error['code'] != '23505') {
          throw const FormatException();
        }
        final lookup = await connection
            .get(
                endpoint.replace(queryParameters: {
                  'select': row.keys.join(','),
                  'id': 'eq.${row['id']}',
                  'organizer_id': 'eq.${session.ownerId}',
                }),
                headers: _eventHeaders(session))
            .timeout(requestTimeout);
        session.check();
        if (lookup.statusCode != 200) throw const FormatException();
        final rows = jsonDecode(lookup.body);
        final existing = rows is List && rows.length == 1 ? rows.single : null;
        if (existing is! Map ||
            !row.entries.every((entry) {
              if (entry.key == 'starts_at') {
                return DateTime.tryParse('${existing[entry.key]}')
                        ?.isAtSameMomentAs(
                            DateTime.parse(entry.value as String)) ==
                    true;
              }
              return existing[entry.key] == entry.value;
            })) {
          throw const FormatException();
        }
      }
      session.check();
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Нийтэлсэн эсэхийг баталж чадсангүй. Нийтлэгдсэн байж болно. '
          'Дахин шалгахад ижил эвентийн төлөвийг баталгаажуулна.');
    } finally {
      if (_eventHttp == null) connection.close();
    }
  }

  Future<EventRsvp> loadRsvp(String eventId,
      {PublicationSession? session}) async {
    _checkReader(session);
    final connection = _eventHttp ?? http.Client();
    final endpoint = Uri.parse('${client.rest.url}/event_rsvps');
    try {
      Future<int> count(String status) async {
        final response = await connection
            .head(
                endpoint.replace(queryParameters: {
                  'event_id': 'eq.$eventId',
                  'status': 'eq.$status',
                }),
                headers: _eventHeaders(session)..['Prefer'] = 'count=exact')
            .timeout(requestTimeout);
        _checkReader(session);
        final value = int.tryParse(
            response.headers['content-range']?.split('/').last ?? '');
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            value == null ||
            value < 0) {
          throw const FormatException();
        }
        return value;
      }

      final going = await count('going');
      final interested = await count('interested');
      String? mine;
      if (session != null) {
        session.check();
        final response = await connection
            .get(
                endpoint.replace(queryParameters: {
                  'select': 'status',
                  'event_id': 'eq.$eventId',
                  'user_id': 'eq.${session.ownerId}',
                  'limit': '2',
                }),
                headers: _eventHeaders(session))
            .timeout(requestTimeout);
        session.check();
        if (response.statusCode != 200) throw const FormatException();
        final rows = jsonDecode(response.body);
        if (rows is! List || rows.length > 1) throw const FormatException();
        if (rows.isNotEmpty) {
          mine = rows.single['status'] as String?;
          if (!const {'going', 'interested'}.contains(mine)) {
            throw const FormatException();
          }
        }
      }
      _checkReader(session);
      return (going: going, interested: interested, mine: mine);
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      _checkReader(session);
      throw const PublicationFailure(
          'Оролцооны мэдээллийг ачаалж чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (_eventHttp == null) connection.close();
    }
  }

  Future<void> setRsvp(
      PublicationSession session, String eventId, String? status) async {
    session.check();
    if (status != null && !const {'going', 'interested'}.contains(status)) {
      throw const PublicationFailure('Оролцооны төлөв буруу байна.');
    }
    final connection = _eventHttp ?? http.Client();
    try {
      final endpoint = Uri.parse('${client.rest.url}/event_rsvps');
      final response = status == null
          ? await connection
              .delete(
                  endpoint.replace(queryParameters: {
                    'event_id': 'eq.$eventId',
                    'user_id': 'eq.${session.ownerId}',
                  }),
                  headers: _eventHeaders(session))
              .timeout(requestTimeout)
          : await connection
              .post(
                endpoint.replace(queryParameters: {
                  'on_conflict': 'event_id,user_id',
                }),
                headers: _eventHeaders(session)
                  ..['Prefer'] = 'resolution=merge-duplicates,return=minimal',
                body: jsonEncode({
                  'event_id': eventId,
                  'user_id': session.ownerId,
                  'status': status
                }),
              )
              .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException();
      }
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Оролцооны өөрчлөлтийг баталж чадсангүй. Төлөвийг дахин ачаалж шалгана уу.');
    } finally {
      if (_eventHttp == null) connection.close();
    }
  }
}
