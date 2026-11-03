import '../../../models/venue.dart';
import '../../../models/venue_story_activity.dart';

/// Merge aliases once after map catalog deduplication. Each story/post has one
/// venue_ref, so adding disjoint ref groups cannot count that content twice.
VenueStoryActivity resolveVenueStoryActivity(
    Venue venue, Map<String, VenueStoryActivity> activities) {
  final refs = {venue.id, ...venue.catalogAliases};
  var count = 0;
  var postCount = 0;
  DateTime? day;
  DateTime? nextExpiry;
  var mixedDays = false;
  for (final ref in refs) {
    final activity = activities[ref];
    if (activity == null) continue;
    count += activity.count;
    postCount += activity.postCount;
    final activityDay = activity.day;
    if (activityDay != null) {
      if (day != null && day != activityDay) mixedDays = true;
      day ??= activityDay;
    }
    final expiry = activity.nextExpiry;
    if (expiry != null && (nextExpiry == null || expiry.isBefore(nextExpiry))) {
      nextExpiry = expiry;
    }
  }
  return VenueStoryActivity(
    count: count,
    postCount: postCount,
    day: mixedDays ? null : day,
    nextExpiry: nextExpiry,
  );
}
