import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/widgets/content_review_notice.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';

void main() {
  const inReview = 'Шалгалтад байна. Модератор баталсны дараа бусдад харагдана.';
  const rejected =
      'Зөвшөөрөөгүй. Дүрмээ шалгаж, агуулгаа засварлан дахин илгээгээрэй.';
  const profileRejected =
      'Профайлын өөрчлөлтийг зөвшөөрөөгүй. Өмнөх баталсан мэдээлэл хэвээр байна.';
  const eventReview =
      'Эвентийг шалгалтад илгээлээ. Модератор баталсны дараа бусдад харагдана.';

  group('publicationFeedback', () {
    test('approved content says it is public now', () {
      for (final kind in [
        SavedContentKind.post,
        SavedContentKind.story,
        SavedContentKind.note,
      ]) {
        expect(publicationFeedback(kind, 'approved'), 'Нийтлэгдлээ');
      }
      expect(publicationFeedback(SavedContentKind.comment, 'approved'),
          'Сэтгэгдэл нэмэгдлээ');
      expect(publicationFeedback(SavedContentKind.review, 'approved'),
          'Үнэлгээ нийтлэгдлээ');
      expect(publicationFeedback(SavedContentKind.profile, 'approved'),
          'Профайл хадгалагдлаа');
    });

    test('pending content says it waits for a moderator', () {
      for (final kind in [
        SavedContentKind.post,
        SavedContentKind.story,
        SavedContentKind.note,
        SavedContentKind.comment,
        SavedContentKind.review,
        SavedContentKind.profile,
      ]) {
        expect(publicationFeedback(kind, 'pending'), inReview);
      }
    });

    test('rejected content keeps the rejected wording', () {
      expect(publicationFeedback(SavedContentKind.post, 'rejected'), rejected);
      expect(
          publicationFeedback(SavedContentKind.comment, 'rejected'), rejected);
      expect(publicationFeedback(SavedContentKind.profile, 'rejected'),
          profileRejected);
    });

    test('unknown status never claims review or publication', () {
      for (final kind in [
        SavedContentKind.post,
        SavedContentKind.comment,
        SavedContentKind.review,
        SavedContentKind.profile,
      ]) {
        expect(publicationFeedback(kind, null), 'Хадгалагдлаа');
        expect(publicationFeedback(kind, 'unexpected'), 'Хадгалагдлаа');
      }
    });

    test('events are always pre-moderated', () {
      for (final status in ['approved', 'pending', 'rejected', null]) {
        expect(
            publicationFeedback(SavedContentKind.event, status), eventReview);
      }
    });

    test('English wording is kept alongside', () {
      const en = ContentReviewStrings.en;
      expect(
          publicationFeedback(SavedContentKind.post, 'approved', strings: en),
          'Published');
      expect(
          publicationFeedback(SavedContentKind.comment, 'approved',
              strings: en),
          'Comment added');
      expect(
          publicationFeedback(SavedContentKind.review, 'approved', strings: en),
          'Review published');
      expect(
          publicationFeedback(SavedContentKind.profile, 'approved',
              strings: en),
          'Profile saved');
      expect(publicationFeedback(SavedContentKind.post, 'pending', strings: en),
          'In review. Others will see it after a moderator approves it.');
      expect(publicationFeedback(SavedContentKind.post, null, strings: en),
          'Saved');
      expect(
          publicationFeedback(SavedContentKind.event, 'approved', strings: en),
          startsWith('Event sent for review'));
    });
  });

  group('savedModerationStatus', () {
    test('reads a returned row, list or JSON body', () {
      expect(
          savedModerationStatus({'moderation_status': 'approved'}), 'approved');
      expect(
          savedModerationStatus([
            {'moderation_status': 'pending'}
          ]),
          'pending');
      expect(savedModerationStatus('[{"moderation_status":"rejected"}]'),
          'rejected');
      expect(savedModerationStatus('{"moderation_status":"approved"}'),
          'approved');
    });

    test('anything else is unknown', () {
      for (final value in <Object?>[
        null,
        '',
        'not json',
        <Object>[],
        [
          {'moderation_status': 'approved'},
          {'moderation_status': 'approved'}
        ],
        {'moderation_status': 'published'},
        {'moderation_status': 1},
        <String, Object>{},
      ]) {
        expect(savedModerationStatus(value), isNull, reason: '$value');
      }
    });
  });

  testWidgets('snackbar shows the mapped message', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showPublicationFeedback(
                        context, SavedContentKind.comment, 'pending'),
                    child: const Text('save'))))));
    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text(inReview), findsOneWidget);
    expect(find.textContaining('Шалгалтад илгээлээ'), findsNothing);
  });
}
