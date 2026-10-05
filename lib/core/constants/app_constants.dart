/// NightOwl UB — app-н тогтмол утгууд
abstract class AppConstants {
  // Supabase
  static const String supabaseUrl    = 'https://jbbdnpsvstwxtgtjoeru.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpiYmRucHN2c3R3eHRndGpvZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNzg1ODIsImV4cCI6MjA5NTY1NDU4Mn0.90qjYby2XNwierEh9XORoP2FEs2LPlRqBC6W74_2oqE';

  // Production can select another licensed provider at build time.
  static const String mapTileUrl = String.fromEnvironment('MAP_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  static const String mapAttribution = String.fromEnvironment('MAP_ATTRIBUTION',
      defaultValue: '© OpenStreetMap contributors');
  static const String mapAttributionUrl = String.fromEnvironment('MAP_ATTRIBUTION_URL',
      defaultValue: 'https://www.openstreetmap.org/copyright');
  static const String publicAppUrl = String.fromEnvironment('PUBLIC_APP_URL',
      defaultValue: 'https://nightowl-ub.netlify.app');

  // OpenStreetMap relation/15638347: Сүхбаатарын талбай (reviewed 2026-10-05).
  static const double ubLat = 47.9188126;
  static const double ubLng = 106.9168967;

  // Story / Check-in expires
  static const Duration storyExpiry   = Duration(hours: 24);
  static const Duration checkinExpiry = Duration(hours: 4);

  // Pagination
  static const int feedPageSize      = 20;
  static const int notifPageSize     = 30;
  static const int dmPageSize        = 50;

  // Animation durations
  static const Duration animFast   = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow   = Duration(milliseconds: 400);

  // Image quality
  static const int imageQuality = 85;
  static const int imageMaxWidth = 1080;

  // Min age
  static const int minAge = 18;

  // Interest chips
  static const List<String> interestOptions = [
    'Bar', 'Live music', 'Cocktail', 'DJ set',
    'Lounge', 'Club', 'Jazz', 'Rooftop',
    'Pub', 'Wine', 'Karaoke', 'Night market',
  ];

}
