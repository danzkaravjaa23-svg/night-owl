/// NightOwl UB — app-н тогтмол утгууд
abstract class AppConstants {
  // Supabase
  static const String supabaseUrl    = 'https://jbbdnpsvstwxtgtjoeru.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpiYmRucHN2c3R3eHRndGpvZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNzg1ODIsImV4cCI6MjA5NTY1NDU4Mn0.90qjYby2XNwierEh9XORoP2FEs2LPlRqBC6W74_2oqE';

  // UB location (Сүхбаатар талбай)
  static const double ubLat = 47.9077;
  static const double ubLng = 106.8832;

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

  // UB venues sample (seeding/demo)
  static const List<Map<String, dynamic>> ubVenues = [
    {
      'name': 'Sugar Lounge',
      'type': 'lounge',
      'lat': 47.9103,
      'lng': 106.8871,
      'district': 'Сүхбаатар дүүрэг',
    },
    {
      'name': 'Mass Club',
      'type': 'nightclub',
      'lat': 47.9045,
      'lng': 106.8923,
      'district': 'Чингэлтэй дүүрэг',
    },
    {
      'name': 'Vertigo Rooftop',
      'type': 'rooftop',
      'lat': 47.9123,
      'lng': 106.8845,
      'district': 'Сүхбаатар дүүрэг',
    },
    {
      'name': 'Brewery Praha',
      'type': 'pub',
      'lat': 47.9001,
      'lng': 106.8912,
      'district': 'Баянгол дүүрэг',
    },
    {
      'name': 'Element Lounge',
      'type': 'lounge',
      'lat': 47.8956,
      'lng': 106.8778,
      'district': 'Хан-Уул дүүрэг',
    },
    {
      'name': 'Rockstar Bar',
      'type': 'bar',
      'lat': 47.9067,
      'lng': 106.8901,
      'district': 'Баянзүрх дүүрэг',
    },
  ];
}
