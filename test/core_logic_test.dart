import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/utils/image_compress_stub.dart';
import 'package:night_owl_ub/core/utils/validators.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';
import 'package:night_owl_ub/features/profile/utils/app_links.dart';
import 'package:night_owl_ub/models/venue.dart';
import 'package:night_owl_ub/core/widgets/network_video.dart';

void main() {
  group('Authentication route boundary', () {
    test('root must not make all paths public', () {
      expect(AppRoutes.isPublic('/'), isTrue);
      expect(AppRoutes.isPublic('/auth/login'), isTrue);
      for (final route in ['/feed', '/profile', '/map', '/settings', '/admin', '/authentic']) {
        expect(AppRoutes.isPublic(route), isFalse, reason: route);
      }
    });
  });
  group('Venue locations', () {
    Venue venue(double? lat, double? lng, {String name = 'Venue'}) => Venue(
      id: 'v1', name: name, type: 'pub', lat: lat, lng: lng, createdAt: DateTime(2026));
    test('reject missing, non-finite, zero and out-of-range coordinates', () {
      for (final value in [venue(null, 106), venue(47, null), venue(91, 106),
        venue(47, 181), venue(double.nan, 106), venue(0, 0)]) {
        expect(value.hasLocation, isFalse);
      }
      expect(venue(47.9, 106.9).hasLocation, isTrue);
    });
    test('recognize only documented load-test name suffix', () {
      expect(venue(47, 106, name: 'Amber Bar #128').isDemo, isTrue);
      expect(venue(47, 106, name: 'Bar #one').isDemo, isFalse);
      expect(venue(47, 106, name: 'Bar 128').isDemo, isFalse);
    });
    test('parser accepts numeric strings and deduplicates venue ids', () {
      final markers = VenueMapMarker.parse('[{"id":"a","lat":"47.9","lng":"106.9"},'
        '{"id":"a","lat":48,"lng":107},{"id":"b","lat":999,"lng":106}]');
      expect(markers, hasLength(1));
      expect(markers.single.point.latitude, 47.9);
      expect(VenueMapMarker.parse('malformed'), isEmpty);
    });
    test('legacy seed pins are removed and reviewed positions are source-linked', () {
      Map<String, dynamic> row(String name, double lat, double lng) =>
        {'id': 'v', 'name': name, 'lat': lat, 'lng': lng};
      expect(Venue.fromJson(row('Mass Club', 47.9045, 106.8923)).hasLocation, isFalse);
      expect(Venue.fromJson(row('Owner venue', 47.9077, 106.8832)).hasLocation, isFalse);
      final reviewed = Venue.fromJson(row('Fat Cat Jazz Club', 47.9192, 106.917));
      expect(reviewed.lat, 47.9152012);
      expect(reviewed.locationSourceUrl, contains('/node/6452841082'));
      final edited = Venue.fromJson(row('Fat Cat Jazz Club', 47.95, 106.95));
      expect(edited.lat, 47.95, reason: 'never override a subsequent owner edit');
      expect(edited.locationSourceUrl, isNull);
    });
    test('overnight hours use Ulaanbaatar local time', () {
      final night = Venue(id: 'v', name: 'Night', type: 'pub', openTime: '18:00',
        closeTime: '01:00', createdAt: DateTime(2026));
      expect(night.isOpenAt(DateTime.utc(2026, 10, 4, 16, 30)), isTrue); // 00:30
      expect(night.isOpenAt(DateTime.utc(2026, 10, 4, 17)), isFalse); // 01:00
      expect(venue(47, 106).isOpenAt(DateTime.utc(2026)), isNull);
    });
  });
  test('profile validation rejects overlong usernames and accepts trimmed input', () {
    expect(Validators.username('  night_owl  '), isNull);
    expect(Validators.username('x' * 21), isNotNull);
    expect(Validators.username('ab'), isNotNull);
  });
  test('invite codes cannot inject extra query arguments', () {
    final uri = Uri.parse(inviteLink('a&admin=true'));
    expect(uri.queryParameters, {'ref': 'a&admin=true'});
  });
  test('video URLs retain their type when query strings are present', () {
    expect(isVideoUrl('https://example.com/video.MP4?token=xyz'), isTrue);
    expect(isVideoUrl('https://example.com/photo.jpg?name=video.mp4'), isFalse);
  });
  test('native PNG input becomes a resized JPEG', () async {
    final original = image.Image(width: 800, height: 400);
    final jpeg = await compressToJpeg(image.encodePng(original), maxDim: 200);
    expect(jpeg.take(2), [0xff, 0xd8]);
    final decoded = image.decodeJpg(jpeg)!;
    expect(decoded.width, 200);
    expect(decoded.height, 100);
  });
}
