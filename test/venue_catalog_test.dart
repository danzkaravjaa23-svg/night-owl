import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/models/venue.dart';

Venue community(
        {String id = '00000000-0000-4000-8000-000000000001',
        String name = 'Fixture Pub',
        double lat = 47.915,
        double lng = 106.92}) =>
    Venue(
      id: id,
      name: name,
      type: 'pub',
      lat: lat,
      lng: lng,
      phone: 'owned phone',
      coverUrl: 'https://owned.example/photo.jpg',
      verified: true,
      rating: 4.4,
      checkinCount: 7,
      createdAt: DateTime.utc(2025),
    );

Venue osm(
        {String id = 'osm:node:1',
        String name = 'Fixture Pub',
        double lat = 47.9151,
        double lng = 106.92}) =>
    Venue.fromJson({
      'id': id,
      'name': name,
      'venue_type': 'pub',
      'lat': lat,
      'lng': lng,
      'community_enabled': false,
      'verified': false,
      'source_label': 'OpenStreetMap',
      'source_url': 'https://www.openstreetmap.org/node/1',
      'source_retrieved_at': '2026-10-05T00:00:00Z',
      'website_url': 'https://mapped.example/',
      'source_opening_hours': 'Mo-Fr 19:00-02:00',
      'address': 'Mapped address',
      'phone': 'mapped phone',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'bundled real catalog parses with complete provenance and no community capabilities',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final venues = await container.read(osmVenueCatalogProvider.future);
    expect(venues, hasLength(270));
    expect(venues.map((v) => v.id).toSet(), hasLength(270));
    expect(
        venues.every((v) =>
            v.hasLocation &&
            !v.communityEnabled &&
            v.sourceLabel == 'OpenStreetMap' &&
            v.sourceUrl != null &&
            v.sourceRetrievedAt != null &&
            v.photos.isEmpty &&
            v.coverUrl == null &&
            !v.verified &&
            v.rating == 0),
        true);
  });

  test(
      'supplemental model never invents rating, open status or community capability',
      () {
    final venue = osm();
    expect(venue.communityEnabled, false);
    expect(venue.sourceLabel, 'OpenStreetMap');
    expect(venue.sourceRetrievedAt, DateTime.utc(2026, 10, 5));
    expect(venue.sourceOpeningHours, 'Mo-Fr 19:00-02:00');
    expect(venue.openTime, isNull);
    expect(venue.isOpenAt(DateTime.utc(2026, 10, 5)), isNull);
    expect(venue.rating, 0);
    expect(venue.verified, false);
  });

  test(
      'near duplicate preserves the backend UUID, community data and owned fields',
      () {
    final server = community();
    final result = mergeVenueCatalog([server], [osm(name: 'Fixture-Pub')]);
    expect(result, hasLength(1));
    final venue = result.single;
    expect(venue.id, server.id);
    expect(venue.communityEnabled, true);
    expect(venue.phone, 'owned phone');
    expect(venue.coverUrl, server.coverUrl);
    expect(venue.rating, 4.4);
    expect(venue.checkinCount, 7);
    expect(venue.verified, true);
    expect(venue.address, 'Mapped address');
    expect(venue.sourceUrl, 'https://www.openstreetmap.org/node/1');
    expect(venue.sourceOpeningHours, 'Mo-Fr 19:00-02:00');
  });

  test(
      'same-name branches remain separate; demo rows and invalid supplements are excluded',
      () {
    final result = mergeVenueCatalog([
      community(),
      community(id: 'demo', name: 'Fixture Pub #700'),
    ], [
      osm(id: 'osm:node:2', lat: 47.925),
      osm(id: 'osm:node:3', name: 'Demo #1'),
      Venue(
          id: 'osm:node:4',
          name: 'Unknown location',
          type: 'pub',
          communityEnabled: false,
          createdAt: DateTime(2026))
    ]);
    expect(result, hasLength(2));
    expect(result.map((v) => v.id),
        containsAll(['00000000-0000-4000-8000-000000000001', 'osm:node:2']));
  });

  test('reviewed source ID can reconcile differing business display names', () {
    final server = Venue.fromJson({
      'id': 'backend-uuid',
      'name': 'Grand Khaan Irish Pub',
      'venue_type': 'pub',
      'lat': 47.9185,
      'lng': 106.9201
    });
    final supplement = Venue.fromJson({
      'id': 'osm:node:13369164710',
      'name': 'Grand Khaan',
      'venue_type': 'pub',
      'lat': 47.9152094,
      'lng': 106.9138958,
      'community_enabled': false,
      'source_label': 'OpenStreetMap',
      'source_url': 'https://www.openstreetmap.org/node/13369164710',
      'source_retrieved_at': '2026-10-05T00:00:00Z'
    });
    expect(mergeVenueCatalog([server], [supplement]), hasLength(1));
  });

  test(
      'server failure returns an honest public catalog with an explicit warning',
      () async {
    final container = ProviderContainer(overrides: [
      venueBackendRowsProvider
          .overrideWith((ref) async => throw StateError('offline')),
      osmVenueCatalogProvider.overrideWith((ref) async => [osm()]),
    ]);
    addTearDown(container.dispose);
    final rows = await container.read(venuesProvider.future);
    expect(rows.single.communityEnabled, false);
    final status = container.read(venueCatalogStatusProvider);
    expect(status.communityUnavailable, true);
    expect(status.supplementUnavailable, false);
    expect(status.supplementalCount, 1);
    expect(status.notice, contains('Сервертэй холбогдож чадсангүй'));
  });

  test(
      'asset failure preserves backend venues and exposes its separate warning',
      () async {
    final container = ProviderContainer(overrides: [
      venueBackendRowsProvider.overrideWith((ref) async => [community()]),
      osmVenueCatalogProvider.overrideWith(
          (ref) async => throw const FormatException('damaged catalog')),
    ]);
    addTearDown(container.dispose);
    final rows = await container.read(venuesProvider.future);
    expect(rows.single.communityEnabled, true);
    expect(
        container.read(venueCatalogStatusProvider).supplementUnavailable, true);
  });

  test(
      'both sources failing remains an error instead of a successful empty list',
      () async {
    final container = ProviderContainer(overrides: [
      venueBackendRowsProvider
          .overrideWith((ref) async => throw StateError('offline')),
      osmVenueCatalogProvider
          .overrideWith((ref) async => throw StateError('damaged')),
    ]);
    addTearDown(container.dispose);
    await expectLater(container.read(venuesProvider.future), throwsStateError);
  });

  test('retry makes a new backend request and clears the fallback warning',
      () async {
    var requests = 0;
    final container = ProviderContainer(overrides: [
      venueBackendRowsProvider.overrideWith((ref) async {
        requests++;
        if (requests == 1) throw StateError('temporary failure');
        return [community()];
      }),
      osmVenueCatalogProvider.overrideWith((ref) async => [osm()]),
    ]);
    addTearDown(container.dispose);
    expect(
        (await container.read(venuesProvider.future)).single.communityEnabled,
        false);
    expect(
        container.read(venueCatalogStatusProvider).communityUnavailable, true);
    container.read(refreshVenueCatalogProvider)();
    expect(
        (await container.read(venuesProvider.future)).single.communityEnabled,
        true);
    expect(requests, 2);
    expect(container.read(venueCatalogStatusProvider).notice, isNull);
  });

  test('failed refresh retains previous rows with both-source failure status',
      () async {
    var failing = false;
    final container = ProviderContainer(overrides: [
      venueBackendRowsProvider.overrideWith((ref) async {
        if (failing) throw StateError('community refresh failure');
        return [community()];
      }),
      osmVenueCatalogProvider.overrideWith((ref) async {
        if (failing) throw StateError('catalog refresh failure');
        return [osm(id: 'osm:node:2', name: 'Another place')];
      }),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(venuesProvider, (previous, next) {},
        fireImmediately: true);
    addTearDown(subscription.close);
    final previousRows = await container.read(venuesProvider.future);
    expect(previousRows, hasLength(2));
    expect(container.read(venueCatalogStatusProvider).notice, isNull);

    failing = true;
    container.read(refreshVenueCatalogProvider)();
    await expectLater(container.read(venuesProvider.future), throwsStateError);
    final state = container.read(venuesProvider);
    expect(state.hasError, true);
    expect(state.hasValue, true);
    expect(state.valueOrNull, previousRows);
    final status = container.read(venueCatalogStatusProvider);
    expect(status.communityUnavailable, true);
    expect(status.supplementUnavailable, true);
    expect(status.supplementalCount, 0);
    expect(status.sourceRetrievedAt, isNull);
    expect(status.notice, contains('шинэчилж чадсангүй'));
    expect(status.notice, isNot(contains('харуулж байна')));
  });

  test(
      'empty fallback warning does not claim public catalog records are available',
      () {
    expect(const VenueCatalogStatus(communityUnavailable: true).notice,
        contains('мэдээлэл одоогоор алга'));
  });

  test('OSM IDs cannot reach backend check-in or checkout calls', () async {
    final notifier = CheckInNotifier();
    addTearDown(notifier.dispose);
    expect(await notifier.checkIn('osm:node:1'),
        contains('хараахан холбогдоогүй'));
    expect(await notifier.checkOut('osm:node:1'),
        contains('хараахан холбогдоогүй'));
  });
}
