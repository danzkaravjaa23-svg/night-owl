/// Map activity describes readable tagged content, never live attendance.
enum VenueStoryLevel {
  sleeping,
  waking,
  lively,
  onFire;

  static VenueStoryLevel forCount(int count) {
    if (count <= 0) return sleeping;
    if (count < 5) return waking;
    if (count < 15) return lively;
    return onFire;
  }

  String get label => switch (this) {
        sleeping => 'Нойрмог',
        waking => 'Сэрж байна',
        lively => 'Идэвхтэй',
        onFire => 'Галтай',
      };

  String get rangeLabel => switch (this) {
        sleeping => '0',
        waking => '1–4',
        lively => '5–14',
        onFire => '15+',
      };
}

class VenueStoryActivity {
  /// Today's active stories plus posts created in the last 168 hours.
  final int count;
  final int postCount;

  /// Keeping the total-count constructor preserves existing story-only callers.
  int get storyCount => count - postCount;
  String get breakdownLabel => '$storyCount story · $postCount post';

  /// Calendar date in Ulaanbaatar, represented without a device-timezone shift.
  final DateTime? day;
  final DateTime? nextExpiry;

  const VenueStoryActivity({
    required this.count,
    this.postCount = 0,
    this.day,
    this.nextExpiry,
  })  : assert(count >= 0),
        assert(postCount >= 0),
        assert(postCount <= count);

  VenueStoryLevel get level => VenueStoryLevel.forCount(count);

  factory VenueStoryActivity.fromJson(Map<String, dynamic> json) {
    final rawStories = json['story_count'];
    // Old cached fixtures omit this key; an explicitly invalid value must fail.
    final rawPosts = json.containsKey('post_count') ? json['post_count'] : 0;
    final rawDay = json['activity_day'];
    final rawExpiry = json['next_expiry'];
    bool validCount(dynamic value) =>
        value is num && value.isFinite && value >= 0 && value.toInt() == value;
    if (!validCount(rawStories) ||
        !validCount(rawPosts) ||
        rawDay is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDay) ||
        rawExpiry is! String) {
      throw const FormatException('Invalid venue map activity');
    }
    final day = DateTime.tryParse('${rawDay}T00:00:00Z');
    final expiry = DateTime.tryParse(rawExpiry);
    if (day == null ||
        day.toIso8601String().substring(0, 10) != rawDay ||
        expiry == null) {
      throw const FormatException('Invalid venue map activity dates');
    }
    final postCount = (rawPosts as num).toInt();
    return VenueStoryActivity(
      count: (rawStories as num).toInt() + postCount,
      postCount: postCount,
      day: day,
      nextExpiry: expiry.toUtc(),
    );
  }
}

/// Server references are not venue names: UUID and OSM aliases remain distinct.
Map<String, VenueStoryActivity> parseVenueStoryActivities(dynamic rows) {
  if (rows is! List) {
    throw const FormatException('Invalid venue story activity response');
  }
  final result = <String, VenueStoryActivity>{};
  for (final row in rows) {
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Invalid venue story activity row');
    }
    final ref = row['venue_ref'];
    if (ref is! String || ref.trim().isEmpty || result.containsKey(ref)) {
      throw const FormatException('Invalid or duplicate venue reference');
    }
    result[ref] = VenueStoryActivity.fromJson(row);
  }
  return Map.unmodifiable(result);
}

/// Poll within a minute, sooner at a story/post expiry or Ulaanbaatar midnight.
Duration nextVenueStoryActivityRefresh(
  DateTime now,
  Iterable<VenueStoryActivity> activities,
) {
  final utc = now.toUtc();
  final local = utc.add(const Duration(hours: 8));
  final midnight = DateTime.utc(local.year, local.month, local.day + 1)
      .subtract(const Duration(hours: 8));
  var delay = const Duration(minutes: 1);
  void consider(DateTime time) {
    final candidate = time.toUtc().difference(utc);
    if (candidate < delay) delay = candidate;
  }

  consider(midnight);
  for (final activity in activities) {
    final expiry = activity.nextExpiry;
    if (expiry != null) consider(expiry);
  }
  // A tiny safety margin avoids re-reading the same boundary on a fast timer.
  return delay < const Duration(seconds: 1)
      ? const Duration(seconds: 1)
      : delay + const Duration(milliseconds: 100);
}
