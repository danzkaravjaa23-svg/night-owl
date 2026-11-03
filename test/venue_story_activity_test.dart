import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/features/map/providers/venue_story_activity_resolver.dart';
import 'package:night_owl_ub/models/venue.dart';
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

  test('legacy count constructors and rows remain story-only', () {
    const activity = VenueStoryActivity(count: 7);
    expect(activity.storyCount, 7);
    expect(activity.postCount, 0);
    expect(activity.breakdownLabel, '7 story · 0 post');
    final parsed = VenueStoryActivity.fromJson(row('x', count: 3));
    expect(parsed.storyCount, 3);
    expect(parsed.postCount, 0);
    expect(parsed.count, 3);
  });

  test('story and rolling post counts combine at level boundaries', () {
    final activity = VenueStoryActivity.fromJson({
      ...row('x', count: 4),
      'post_count': 11,
    });
    expect(activity.storyCount, 4);
    expect(activity.postCount, 11);
    expect(activity.count, 15);
    expect(activity.level, VenueStoryLevel.onFire);
    expect(activity.breakdownLabel, '4 story · 11 post');
    final postsOnly = VenueStoryActivity.fromJson({
      ...row('x', count: 0),
      'post_count': 5,
    });
    expect(postsOnly.count, 5);
    expect(postsOnly.storyCount, 0);
    expect(postsOnly.level, VenueStoryLevel.lively);
  });

  test('supplied malformed post counts fail instead of becoming legacy zero',
      () {
    for (final count in [
      -1,
      .5,
      '5',
      null,
      double.infinity,
      double.nan,
      true
    ]) {
      expect(
        () => VenueStoryActivity.fromJson({...row('x'), 'post_count': count}),
        throwsFormatException,
      );
    }
    expect(
      VenueStoryActivity.fromJson({...row('x', count: 0), 'post_count': 0})
          .count,
      0,
    );
  });

  test('duplicate aliases sum each content group once and retain first expiry',
      () {
    final day = DateTime.utc(2026, 11, 3);
    final storyExpiry = DateTime.utc(2026, 11, 3, 12);
    final postExpiry = DateTime.utc(2026, 11, 3, 4, 1);
    final venue = Venue(
      id: 'community',
      name: 'Same branch',
      type: 'bar',
      lat: 47.918,
      lng: 106.918,
      catalogAliases: const ['community', 'osm:node:1', 'osm:node:1'],
      createdAt: day,
    );
    final activity = resolveVenueStoryActivity(venue, {
      'community': VenueStoryActivity(
          count: 7, postCount: 3, day: day, nextExpiry: storyExpiry),
      'osm:node:1': VenueStoryActivity(
          count: 8, postCount: 6, day: day, nextExpiry: postExpiry),
      'elsewhere': const VenueStoryActivity(count: 100, postCount: 100),
    });
    expect(activity.count, 15);
    expect(activity.storyCount, 6);
    expect(activity.postCount, 9);
    expect(activity.nextExpiry, postExpiry);
    expect(activity.day, day);
    expect(activity.level, VenueStoryLevel.onFire);
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

  test(
      'post-only rolling deadline refreshes before the story calendar boundary',
      () {
    final now = DateTime.utc(2026, 11, 3, 4);
    final activities = parseVenueStoryActivities([
      {
        ...row('x', count: 0),
        'post_count': 1,
        'next_expiry': '2026-11-03T04:00:03Z',
      },
      {
        ...row('y', count: 1),
        'post_count': 2,
        'next_expiry': '2026-11-03T04:00:30Z',
      },
    ]);
    expect(nextVenueStoryActivityRefresh(now, activities.values),
        const Duration(milliseconds: 3100));
    expect(activities['x']!.day, DateTime.utc(2026, 11, 3),
        reason:
            'The UB day identifies today’s stories, not a post cutoff day.');
  });
}
