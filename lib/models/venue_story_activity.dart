/// Map activity describes readable stories, never a live attendance estimate.
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
  final int count;

  /// Calendar date in Ulaanbaatar, represented without a device-timezone shift.
  final DateTime? day;
  final DateTime? nextExpiry;

  const VenueStoryActivity({required this.count, this.day, this.nextExpiry})
      : assert(count >= 0);

  VenueStoryLevel get level => VenueStoryLevel.forCount(count);

  factory VenueStoryActivity.fromJson(Map<String, dynamic> json) {
    final rawCount = json['story_count'];
    final rawDay = json['activity_day'];
    final rawExpiry = json['next_expiry'];
    if (rawCount is! num ||
        !rawCount.isFinite ||
        rawCount < 0 ||
        rawCount.toInt() != rawCount ||
        rawDay is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDay) ||
        rawExpiry is! String) {
      throw const FormatException('Invalid venue story activity');
    }
    final day = DateTime.tryParse('${rawDay}T00:00:00Z');
    final expiry = DateTime.tryParse(rawExpiry);
    if (day == null ||
        day.toIso8601String().substring(0, 10) != rawDay ||
        expiry == null) {
      throw const FormatException('Invalid venue story activity dates');
    }
    return VenueStoryActivity(
      count: rawCount.toInt(),
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

/// Poll within a minute, and sooner at an expiry or Ulaanbaatar midnight.
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
