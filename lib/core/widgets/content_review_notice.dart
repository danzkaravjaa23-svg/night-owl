import 'package:flutter/material.dart';

/// Author-facing state; approval never changes the original publication clock.
class ContentReviewNotice extends StatelessWidget {
  final String status;
  final bool onDark;
  final bool profile;
  const ContentReviewNotice(
      {super.key,
      required this.status,
      this.onDark = false,
      this.profile = false});
  @override
  Widget build(BuildContext context) {
    if (status == 'approved') return const SizedBox.shrink();
    final rejected = status == 'rejected';
    const s = ContentReviewStrings.mn;
    final text = profile
        ? rejected
            ? s.profileRejected
            : s.profilePending
        : rejected
            ? s.rejected
            : s.pending;
    final color =
        onDark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(rejected ? Icons.info_outline : Icons.schedule_rounded,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, height: 1.4, color: color))),
        ]));
  }
}

/// Review and post-save wording, Mongolian first with the English kept
/// alongside (same pattern as AppStrings).
class ContentReviewStrings {
  final String locale;
  const ContentReviewStrings._(this.locale);
  static const ContentReviewStrings en = ContentReviewStrings._('en');
  static const ContentReviewStrings mn = ContentReviewStrings._('mn');

  // ─── Per-item badge ───
  String get pending => _t(
      'In review · Others will see it after a moderator approves it.',
      'Шалгаж байна · Модератор баталсны дараа бусдад харагдана.');
  String get rejected => _t(
      'Not approved. Check the rules, edit it and submit again.',
      'Зөвшөөрөөгүй. Дүрмээ шалгаж, агуулгаа засварлан дахин илгээгээрэй.');
  String get profilePending => _t(
      'Your profile changes are in review. They become public after a moderator approves them.',
      'Профайлын өөрчлөлтийг шалгаж байна. Модератор баталсны дараа нийтэд харагдана.');
  String get profileRejected => _t(
      'Profile changes were not approved. Your previously approved details stay as they were.',
      'Профайлын өөрчлөлтийг зөвшөөрөөгүй. Өмнөх баталсан мэдээлэл хэвээр байна.');

  // ─── Post-save confirmation ───
  String get published => _t('Published', 'Нийтлэгдлээ');
  String get commentAdded => _t('Comment added', 'Сэтгэгдэл нэмэгдлээ');
  String get reviewPublished => _t('Review published', 'Үнэлгээ нийтлэгдлээ');
  String get profileSaved => _t('Profile saved', 'Профайл хадгалагдлаа');
  /// Neutral on purpose: 'pending' means a hold under publish-immediately
  /// moderation, but it is also every save's normal result when the backend
  /// runs review-before-publish (publish_immediately=false or no config row),
  /// so the wording must not suggest this item tripped a filter.
  String get inReview => _t(
      'In review. Others will see it after a moderator approves it.',
      'Шалгалтад байна. Модератор баталсны дараа бусдад харагдана.');
  String get eventInReview => _t(
      'Event sent for review. Others will see it after a moderator approves it.',
      'Эвентийг шалгалтад илгээлээ. Модератор баталсны дараа бусдад харагдана.');
  String get saved => _t('Saved', 'Хадгалагдлаа');

  String _t(String en, String mn) => locale == 'mn' ? mn : en;
}

/// What the author just saved, so the confirmation can name it.
enum SavedContentKind { post, story, note, comment, review, profile, event }

/// Post-save confirmation for [kind] given the saved row's moderation_status.
///
/// Ordinary content is public as soon as it is saved unless the server keeps
/// it in review ('pending'), so the server's answer decides the message.
/// 'pending' gets one neutral sentence because it is either a hold or the
/// normal result while the backend reviews before publishing. Events (like
/// venues) are always reviewed before anyone else sees them. When the status
/// is unknown the message only says the save worked.
String publicationFeedback(SavedContentKind kind, String? status,
    {ContentReviewStrings strings = ContentReviewStrings.mn}) {
  if (kind == SavedContentKind.event) return strings.eventInReview;
  return switch (status) {
    'approved' => switch (kind) {
        SavedContentKind.comment => strings.commentAdded,
        SavedContentKind.review => strings.reviewPublished,
        SavedContentKind.profile => strings.profileSaved,
        _ => strings.published,
      },
    'pending' => strings.inReview,
    'rejected' => kind == SavedContentKind.profile
        ? strings.profileRejected
        : strings.rejected,
    _ => strings.saved,
  };
}

void showPublicationFeedback(
        BuildContext context, SavedContentKind kind, String? status) =>
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(publicationFeedback(kind, status))));
