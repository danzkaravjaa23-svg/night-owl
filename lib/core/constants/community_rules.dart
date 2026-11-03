/// A declared adult-only community agreement. This is not age verification.
abstract final class CommunityRules {
  static const version = '2026-11-03';

  static bool isAccepted(Map<String, dynamic>? metadata) =>
      metadata?['adult_confirmed'] == true &&
      metadata?['community_rules_version'] == version;

  static Map<String, dynamic> acceptance(DateTime now) => {
        'adult_confirmed': true,
        'community_rules_version': version,
        'community_rules_accepted_at': now.toUtc().toIso8601String(),
      };
}
