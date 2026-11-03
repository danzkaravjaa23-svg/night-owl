import '../../../models/venue.dart';
import '../../../models/venue_story_activity.dart';

/// Merge aliases once after map catalog deduplication. A story has one
/// venue_ref, so adding disjoint ref groups cannot count that story twice.
VenueStoryActivity resolveVenueStoryActivity(
    Venue venue, Map<String, VenueStoryActivity> activities) {
  final refs = {venue.id, ...venue.catalogAliases};
  var count = 0;
  for (final ref in refs) {
    count += activities[ref]?.count ?? 0;
  }
  return VenueStoryActivity(count: count);
}
