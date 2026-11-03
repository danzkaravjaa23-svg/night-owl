import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/map/data/venue_operating_reviews.dart';
import 'package:night_owl_ub/features/map/widgets/venue_operating_review.dart';

Map<String, dynamic> reviewFixture() => {
      'venue_ref': 'osm:node:1',
      'status': 'evidence_recent_activity',
      'summary': 'Албан ёсны сайтад огноотой арга хэмжээний мэдээлэл бий.',
      'checked_at': '2026-11-03T04:16:54Z',
      'evidence_date': '2026-10-29',
      'published_hours': {
        'opens': '18:00',
        'closes': '01:00',
        'weekday_note': 'Үйлчлэх өдрүүд, онцгой хуваарь тодорхойгүй.',
      },
      'sources': [
        {
          'label': 'Албан ёсны вэбсайт',
          'kind': 'official',
          'url': 'https://venue.example.test/events',
        }
      ],
    };

VenueOperatingReviewCatalog catalogOf(List<Map<String, dynamic>> reviews) =>
    VenueOperatingReviewCatalog.parse(
      jsonEncode({'schema_version': 1, 'reviews': reviews}),
    );

DateTime reviewNow() => DateTime.utc(2026, 11, 3, 6);

Future<void> pumpReview(
  WidgetTester tester, {
  List<String> refs = const ['osm:node:1'],
  VenueOperatingReviewLoader? loader,
  Future<bool> Function(Uri)? openUri,
  DateTime Function()? now,
  Brightness brightness = Brightness.dark,
  double width = 390,
  double scale = 1,
  GlobalKey? capture,
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final panel = Padding(
    padding: const EdgeInsets.all(16),
    child: VenueOperatingReview(
      venueRefs: refs,
      loader: loader ?? () async => catalogOf([reviewFixture()]),
      openUri: openUri,
      now: now ?? reviewNow,
    ),
  );
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: RepaintBoundary(
      key: capture,
      child: Scaffold(
        appBar: AppBar(title: const Text('Fat Cat Jazz Club')),
        body: SingleChildScrollView(child: panel),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_VENUE_REVIEW')) {
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });

  test('bundled reviews contain nine exact listings and no proposed matches',
      () {
    final catalog = VenueOperatingReviewCatalog.parse(
      File('assets/data/venue_operating_reviews.json').readAsStringSync(),
    );
    expect(catalog.reviews.length, 9);
    expect(catalog.reviews.containsKey('osm:node:11140275505'), isFalse);
    expect(catalog.reviews.containsKey('osm:node:13369164710'), isFalse);
    expect(
      catalog.reviews.values
          .where((r) => r.status == VenueOperatingEvidence.recentActivity)
          .map((r) => r.venueRef),
      ['osm:node:6452841082'],
    );
    expect(
      catalog.reviews.values
          .where((r) => r.status == VenueOperatingEvidence.publishedHours)
          .length,
      2,
    );
    expect(
      catalog.reviews.values.every(
        (r) => r.freshnessAt(reviewNow()) == VenueReviewFreshness.current,
      ),
      isTrue,
    );
  });

  test('only exact OSM references or safe canonical source URLs match', () {
    expect(canonicalOperatingVenueRef('osm:node:1'), 'osm:node:1');
    expect(
      canonicalOperatingVenueRef('https://www.openstreetmap.org/way/42'),
      'osm:way:42',
    );
    for (final value in [
      'Fat Cat Jazz Club',
      'osm:node:0',
      'osm:node:1/other',
      'https://user:pass@www.openstreetmap.org/node/1',
      'https://www.openstreetmap.org.evil.test/node/1',
      'https://www.openstreetmap.org:444/node/1',
      'https://www.openstreetmap.org/node/1?x=2',
      'https://www.openstreetmap.org/node/1#map',
      'javascript:alert(1)',
    ]) {
      expect(canonicalOperatingVenueRef(value), isNull, reason: value);
    }
  });

  test('aliases deduplicate a match and conflicting businesses stay uncertain',
      () {
    final other = reviewFixture()..['venue_ref'] = 'osm:way:2';
    final catalog = catalogOf([reviewFixture(), other]);
    final selected = catalog.select([
      'backend-uuid',
      'osm:node:1',
      'https://www.openstreetmap.org/node/1',
      'osm:node:1',
    ]);
    expect(selected.review?.venueRef, 'osm:node:1');
    expect(selected.conflicting, isFalse);
    final conflict = catalog.select(['osm:node:1', 'osm:way:2']);
    expect(conflict.conflicting, isTrue);
    expect(conflict.review, isNull);
    expect(catalog.select(['osm:node:99']).review, isNull);
  });

  final invalidMutations = <String, void Function(Map<String, dynamic>)>{
    'unknown status': (r) => r['status'] = 'open_now',
    'bad ID': (r) => r['venue_ref'] = 'osm:node:-1',
    'invalid date': (r) => r['evidence_date'] = '2026-02-30',
    'future evidence': (r) => r['evidence_date'] = '2026-11-04',
    'invalid timestamp': (r) => r['checked_at'] = '2026-11-03T25:00:00Z',
    'timezone missing': (r) => r['checked_at'] = '2026-11-03T04:16:54',
    'missing official date': (r) => r['evidence_date'] = null,
    'unofficial recent activity': (r) =>
        (r['sources'] as List).first['kind'] = 'secondary_directory',
    'invalid opening time': (r) => r['published_hours']['opens'] = '25:00',
    'invalid closing time': (r) => r['published_hours']['closes'] = '01:60',
    'missing published schedule': (r) {
      r['status'] = 'published_hours_only';
      r['published_hours'] = null;
    },
  };
  for (final entry in invalidMutations.entries) {
    test('rejects ${entry.key}', () {
      final row = reviewFixture();
      entry.value(row);
      expect(() => catalogOf([row]), throwsFormatException);
    });
  }

  for (final url in [
    'javascript:alert(1)',
    'file:///tmp/source',
    'https://user:password@example.test/source',
    'https://example.test/white space',
    'https:///no-host',
  ]) {
    test('rejects unsafe source $url', () {
      final row = reviewFixture();
      (row['sources'] as List).first['url'] = url;
      expect(() => catalogOf([row]), throwsFormatException);
    });
  }

  test('duplicate entries and invalid catalog schema are rejected', () {
    expect(
      () => catalogOf([reviewFixture(), reviewFixture()]),
      throwsFormatException,
    );
    expect(
      () => VenueOperatingReviewCatalog.parse('{"schema_version":2}'),
      throwsFormatException,
    );
  });

  test('stale review, old activity and a future clock are never current', () {
    final row = catalogOf([reviewFixture()]).reviews.values.single;
    expect(row.freshnessAt(reviewNow()), VenueReviewFreshness.current);
    expect(
        row.freshnessAt(DateTime.utc(2026, 12, 5)), VenueReviewFreshness.stale);
    expect(row.freshnessAt(DateTime.utc(2026, 11, 2)),
        VenueReviewFreshness.future);
    // A freshly checked page cannot make its old event become recent.
    final oldActivity = reviewFixture()..['evidence_date'] = '2026-09-01';
    expect(
        catalogOf([oldActivity]).reviews.values.single.freshnessAt(reviewNow()),
        VenueReviewFreshness.stale);
  });

  testWidgets('unreviewed and unavailable information are different states',
      (tester) async {
    await pumpReview(tester, refs: ['osm:node:99']);
    expect(find.text('Үйл ажиллагаа баталгаажаагүй'), findsOneWidget);
    expect(find.text('Мэдээлэл уншигдсангүй'), findsNothing);
    await pumpReview(tester, loader: () async => throw StateError('offline'));
    expect(find.text('Мэдээлэл уншигдсангүй'), findsOneWidget);
    expect(find.text('Үйл ажиллагаа баталгаажаагүй'), findsNothing);
    expect(find.textContaining('газар хаалттай гэсэн үг биш'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dated evidence shows caveats, source and safe external link',
      (tester) async {
    final opened = <Uri>[];
    await pumpReview(tester, openUri: (uri) async {
      opened.add(uri);
      return true;
    });
    expect(find.text('Огноотой үйл ажиллагааны мэдээлэл бий'), findsOneWidget);
    expect(find.text('Мэдээллийн огноо: 2026-10-29'), findsOneWidget);
    expect(find.textContaining('яг одоо нээлттэй эсэхийг батлахгүй'),
        findsOneWidget);
    expect(
        find.text('Эх сурвалжид нийтэлсэн цаг: 18:00 – 01:00'), findsOneWidget);
    await tester.tap(find.text('Албан ёсны вэбсайт'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://venue.example.test/events');
    expect(tester.takeException(), isNull);
  });

  for (final reviewed in [true, false]) {
    testWidgets(
        'failed catalog can retry to ${reviewed ? 'review' : 'unknown'}',
        (tester) async {
      var attempts = 0;
      await pumpReview(
        tester,
        refs: [reviewed ? 'osm:node:1' : 'osm:node:99'],
        loader: () async {
          if (++attempts == 1) throw StateError('temporary read failure');
          return catalogOf([reviewFixture()]);
        },
      );
      expect(find.text('Мэдээлэл уншигдсангүй'), findsOneWidget);
      expect(find.text('Дахин унших'), findsOneWidget);
      await tester.tap(find.text('Дахин унших'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Мэдээлэл уншигдсангүй'), findsNothing);
      expect(find.text('Дахин унших'), findsNothing);
      expect(
          find.text(reviewed
              ? 'Огноотой үйл ажиллагааны мэдээлэл бий'
              : 'Үйл ажиллагаа баталгаажаагүй'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('published hours do not imply a current open status',
      (tester) async {
    final row = reviewFixture()
      ..['status'] = 'published_hours_only'
      ..['evidence_date'] = null;
    await pumpReview(tester, loader: () async => catalogOf([row]));
    expect(find.text('Нийтэлсэн цагийн мэдээлэл бий'), findsOneWidget);
    expect(find.text('Үйлчлэх өдрүүд, онцгой хуваарь тодорхойгүй.'),
        findsOneWidget);
    expect(find.text('Огноотой үйл ажиллагааны мэдээлэл бий'), findsNothing);
  });

  testWidgets('stale, future and conflicting reviews lose current status title',
      (tester) async {
    await pumpReview(tester, now: () => DateTime.utc(2026, 12, 10));
    expect(find.text('Мэдээллийг дахин нягтлах хэрэгтэй'), findsOneWidget);
    expect(find.text('Огноотой үйл ажиллагааны мэдээлэл бий'), findsNothing);
    await pumpReview(tester, now: () => DateTime.utc(2026, 11, 2));
    expect(find.text('Мэдээллийн огноо баталгаажаагүй'), findsOneWidget);
    final other = reviewFixture()..['venue_ref'] = 'osm:way:2';
    await pumpReview(tester,
        refs: ['osm:node:1', 'osm:way:2'],
        loader: () async => catalogOf([reviewFixture(), other]));
    expect(find.text('Байршлыг дахин нягтлах шаардлагатай'), findsOneWidget);
    expect(find.text('Албан ёсны вэбсайт'), findsNothing);
  });

  testWidgets('source failures are retryable and old link errors stay scoped',
      (tester) async {
    var attempts = 0;
    await pumpReview(tester, openUri: (_) async => ++attempts > 1);
    await tester.tap(find.text('Албан ёсны вэбсайт'));
    await tester.pumpAndSettle();
    expect(
        find.text('Эх сурвалж нээгдсэнгүй. Дахин оролдоорой.'), findsOneWidget);
    await tester.tap(find.text('Албан ёсны вэбсайт'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
        find.text('Эх сурвалж нээгдсэнгүй. Дахин оролдоорой.'), findsNothing);

    final completion = Completer<bool>();
    await pumpReview(tester, openUri: (_) => completion.future);
    await tester.tap(find.text('Албан ёсны вэбсайт'));
    await tester.pump();
    await pumpReview(tester, refs: ['osm:node:99']);
    completion.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Үйл ажиллагаа баталгаажаагүй'), findsOneWidget);
    expect(
        find.text('Эх сурвалж нээгдсэнгүй. Дахин оролдоорой.'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final width in [390.0, 320.0]) {
      testWidgets('review fits $width at large text in $brightness',
          (tester) async {
        final capture = GlobalKey();
        await pumpReview(tester,
            refs: ['osm:node:6452841082'],
            loader: () async => VenueOperatingReviewCatalog.parse(
                File('assets/data/venue_operating_reviews.json')
                    .readAsStringSync()),
            brightness: brightness,
            width: width,
            scale: width == 320 ? 1.5 : 1,
            capture: capture,
            height: 1100);
        expect(find.text('Албан ёсны вэбсайт'), findsOneWidget);
        await tester.ensureVisible(find.text('Албан ёсны вэбсайт'));
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_VENUE_REVIEW')) {
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final folder = Directory('build/audit/2026-11-03/venue-refresh');
            await folder.create(recursive: true);
            await File('${folder.path}/venue-review-${brightness.name}-'
                    '${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
