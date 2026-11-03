import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/discovery/widgets/venue_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

JsonRow venue(String ref, String name, {String? id}) => {
      'ref': ref,
      'name': name,
      if (id != null) 'venue_id': id,
      'address': 'Улаанбаатар',
    };

void main() {
  Future<void> pumpPicker(WidgetTester tester, VenueCatalogLoader loader,
      {String? selectedRef}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DiscoveryVenuePicker(
                loader: loader, selectedRef: selectedRef))));
    await tester.pumpAndSettle();
  }

  test('catalog pagination has deterministic order and validates bounds',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://example.test', 'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode([]), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    final service = DiscoveryService(client: client);
    await service.catalog(query: 'Night', offset: 60, limit: 60);
    expect(requests.single.url.queryParameters, containsPair('offset', '60'));
    expect(requests.single.url.queryParameters, containsPair('limit', '60'));
    expect(requests.single.url.queryParameters,
        containsPair('order', 'name.asc.nullslast,ref.asc.nullslast'));
    await expectLater(service.catalog(offset: -1), throwsArgumentError);
    await expectLater(service.catalog(limit: 101), throwsArgumentError);
    expect(requests, hasLength(1));
  });

  testWidgets('selection returns canonical OSM ref and marks current choice',
      (tester) async {
    JsonRow? picked;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      picked = await pickDiscoveryVenue(context,
                          selectedRef: 'osm:node:123',
                          loader: (
                                  {required query,
                                  required offset,
                                  required limit}) async =>
                              [
                                venue(
                                    'osm:node:123', 'Газрын зураг дахь газар'),
                                venue('community-id', 'Community газар',
                                    id: 'community-id'),
                              ]);
                    },
                    child: const Text('Нээх'))))));
    await tester.tap(find.text('Нээх'));
    await tester.pumpAndSettle();
    expect(find.text('Сонгосон'), findsOneWidget);
    expect(
        tester
            .widget<ListTile>(
                find.widgetWithText(ListTile, 'Газрын зураг дахь газар'))
            .selected,
        isTrue);
    await tester.tap(find.text('Газрын зураг дахь газар'));
    await tester.pumpAndSettle();
    expect(picked?['ref'], 'osm:node:123');
    expect(picked?.containsKey('venue_id'), isFalse);
  });

  testWidgets(
      'search hides old choices during debounce and ignores stale responses',
      (tester) async {
    final first = Completer<List<JsonRow>>();
    final second = Completer<List<JsonRow>>();
    final queries = <String>[];
    await pumpPicker(tester, (
        {required query, required offset, required limit}) {
      queries.add(query);
      return switch (query) {
        'first' => first.future,
        'second' => second.future,
        _ => Future.value([venue('initial', 'Эхний газар')]),
      };
    });
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    expect(find.text('Эхний газар'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'second');
    first.complete([venue('old', 'Хоцорсон газар')]);
    await tester.pump();
    expect(find.text('Хоцорсон газар'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    second.complete([venue('new', 'Шинэ газар')]);
    await tester.pumpAndSettle();
    expect(queries, ['', 'first', 'second']);
    expect(find.text('Шинэ газар'), findsOneWidget);
    expect(find.text('Хоцорсон газар'), findsNothing);
    await tester.tap(find.byTooltip('Хайлтыг цэвэрлэх'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(queries.last, '');
    expect(find.text('Эхний газар'), findsOneWidget);
  });

  testWidgets('catalog failure is retryable and does not masquerade as empty',
      (tester) async {
    var attempts = 0;
    await pumpPicker(tester, (
        {required query, required offset, required limit}) async {
      if (++attempts == 1) throw StateError('offline');
      return [venue('restored', 'Сэргэсэн газар')];
    });
    expect(find.text('Дахин оролдох'), findsOneWidget);
    expect(find.textContaining('Газар олдсонгүй'), findsNothing);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Сэргэсэн газар'), findsOneWidget);
  });

  testWidgets('pagination retries the same offset without duplicating rows',
      (tester) async {
    final offsets = <int>[];
    var failed = false;
    await pumpPicker(tester, (
        {required query, required offset, required limit}) async {
      offsets.add(offset);
      if (offset == 0) {
        return List.generate(limit, (i) => venue('ref-$i', 'Газар $i'));
      }
      if (!failed) {
        failed = true;
        throw StateError('offline');
      }
      return [venue('ref-60', 'Хуудас хоёр')];
    });
    final listScroll = find.descendant(
        of: find.byType(ListView), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Илүү олон газар'), 400,
        scrollable: listScroll);
    await tester.tap(find.text('Илүү олон газар'));
    await tester.pumpAndSettle();
    expect(find.text('Дахин оролдох'), findsOneWidget);
    await tester.ensureVisible(find.text('Дахин оролдох'));
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 60, 60]);
    await tester.scrollUntilVisible(find.text('Хуудас хоёр'), 200,
        scrollable: listScroll);
    expect(find.text('Хуудас хоёр'), findsOneWidget);
    expect(find.text('Илүү олон газар'), findsNothing);
  });

  testWidgets('late request completion after picker closes is ignored',
      (tester) async {
    final pending = Completer<List<JsonRow>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DiscoveryVenuePicker(
                loader: ({required query, required offset, required limit}) =>
                    pending.future))));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete([venue('late', 'Хоцорсон газар')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'actual location sheet fits a small screen with keyboard and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 640),
                viewInsets: EdgeInsets.only(bottom: 300),
                textScaler: TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => pickDiscoveryVenue(context,
                        title: 'Story-гийн байршил',
                        helperText:
                            'Байршил нэмбэл өнөөдрийн газрын зургийн идэвхэд тооцогдоно.',
                        loader: (
                                {required query,
                                required offset,
                                required limit}) async =>
                            [
                              venue('canonical', 'Сонгох газар'),
                            ]),
                    child: const Text('Нээх'))))));
    await tester.tap(find.text('Нээх'));
    await tester.pumpAndSettle();
    expect(find.text('Story-гийн байршил'), findsOneWidget);
    expect(find.text('Сонгох газар'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Хаах'));
    await tester.pumpAndSettle();
    expect(find.text('Story-гийн байршил'), findsNothing);
  });
}
