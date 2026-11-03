import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/models/venue_story_activity.dart';

void main() {
  test('four activity levels have exact boundaries and nonattendance labels',
      () {
    for (final count in [0, 1, 4, 5, 14, 15, 1000]) {
      expect(
        VenueStoryActivity(count: count).level,
        switch (count) {
          0 => VenueStoryLevel.sleeping,
          1 || 4 => VenueStoryLevel.waking,
          5 || 14 => VenueStoryLevel.lively,
          _ => VenueStoryLevel.onFire,
        },
      );
    }
    expect(VenueStoryLevel.values.map((v) => v.rangeLabel),
        ['0', '1–4', '5–14', '15+']);
    expect(VenueStoryLevel.values.every((v) => v.label.isNotEmpty), isTrue);
  });

  Map<String, dynamic> row(String ref, {dynamic count = 5}) => {
        'venue_ref': ref,
        'story_count': count,
        'activity_day': '2026-11-03',
        'next_expiry': '2026-11-03T23:00:00+08:00',
      };

  test('source and community UUID identities remain distinct, no name merge',
      () {
    final data = parseVenueStoryActivities([
      row('20000000-0000-0000-0000-000000000001'),
      row('osm:node:123', count: 2),
    ]);
    expect(data, hasLength(2));
    expect(data['osm:node:123']!.count, 2);
    expect(data['osm:node:123']!.day, DateTime.utc(2026, 11, 3));
    expect(data['osm:node:123']!.nextExpiry, DateTime.utc(2026, 11, 3, 15));
    expect(() => data.clear(), throwsUnsupportedError);
  });

  test('malformed or duplicate responses fail rather than inventing zeros', () {
    for (final count in [-1, 0.5, '5', null, double.infinity]) {
      expect(() => parseVenueStoryActivities([row('x', count: count)]),
          throwsFormatException);
    }
    expect(() => parseVenueStoryActivities([row('x'), row('x')]),
        throwsFormatException);
    expect(() => parseVenueStoryActivities([row(' ')]), throwsFormatException);
    expect(() => parseVenueStoryActivities(null), throwsFormatException);
    expect(
        () => parseVenueStoryActivities([
              {...row('x'), 'activity_day': '2026-02-30'}
            ]),
        throwsFormatException);
    expect(parseVenueStoryActivities([]), isEmpty);
  });

  test('refresh follows Ulaanbaatar midnight regardless of device zone', () {
    final delay = nextVenueStoryActivityRefresh(
        DateTime.utc(2026, 11, 3, 15, 59, 58), []);
    expect(delay, const Duration(milliseconds: 2100));
    expect(nextVenueStoryActivityRefresh(DateTime.utc(2026, 11, 3, 16), []),
        const Duration(milliseconds: 60100));
  });

  test('nearest expiry wins and elapsed expiries avoid a busy retry loop', () {
    final now = DateTime.utc(2026, 11, 3, 4);
    expect(
      nextVenueStoryActivityRefresh(now, [
        VenueStoryActivity(
            count: 3, nextExpiry: now.add(const Duration(seconds: 20))),
        VenueStoryActivity(
            count: 1, nextExpiry: now.add(const Duration(seconds: 5))),
      ]),
      const Duration(milliseconds: 5100),
    );
    expect(
        nextVenueStoryActivityRefresh(
            now, [VenueStoryActivity(count: 1, nextExpiry: now)]),
        const Duration(seconds: 1));
  });
}
