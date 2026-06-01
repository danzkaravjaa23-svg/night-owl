import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Веб бус fallback — Google Maps-г browser/апп-аар нээнэ.
class GoogleMapView extends StatelessWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson;
  const GoogleMapView({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 13,
    this.markersJson = '[]',
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.map_outlined, size: 64, color: AppColors.textTertiary),
      const SizedBox(height: 16),
      Text('Газрын зураг', style: AppTextStyles.h2),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: () => launchUrl(
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
          mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(14)),
          child: Text('Google Maps нээх',
            style: AppTextStyles.btn.copyWith(color: Colors.white))),
      ),
    ]),
  );
}
