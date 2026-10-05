/// Reviewed public map data. Only replace the exact legacy seed positions;
/// coordinates subsequently edited by a venue owner remain authoritative.
class VenueLocation {
  final double? lat;
  final double? lng;
  final String? sourceUrl;
  const VenueLocation(this.lat, this.lng, {this.sourceUrl});

  static VenueLocation resolve(String name, double? lat, double? lng) {
    final key = name.trim().toLowerCase();
    if (key == 'grand khaan irish pub' && lat == 47.9185 && lng == 106.9201) {
      return const VenueLocation(47.9152094, 106.9138958,
        sourceUrl: 'https://www.openstreetmap.org/node/13369164710');
    }
    if (key == 'fat cat jazz club' && lat == 47.9192 && lng == 106.917) {
      return const VenueLocation(47.9152012, 106.9174411,
        sourceUrl: 'https://www.openstreetmap.org/node/6452841082');
    }
    const seeds = {
      'sugar lounge': (47.9103, 106.8871),
      'mass club': (47.9045, 106.8923),
      'vertigo rooftop': (47.9123, 106.8845),
      'brewery praha': (47.9001, 106.8912),
      'element lounge': (47.8956, 106.8778),
      'rockstar bar': (47.9067, 106.8901),
    };
    final seed = seeds[key];
    if ((seed != null && lat == seed.$1 && lng == seed.$2) ||
        (lat == 47.9077 && lng == 106.8832)) {
      return const VenueLocation(null, null);
    }
    return VenueLocation(lat, lng);
  }
}
