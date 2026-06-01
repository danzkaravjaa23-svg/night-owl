import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class BarScreen extends StatefulWidget {
  final String venueId;
  const BarScreen({super.key, required this.venueId});
  @override
  State<BarScreen> createState() => _BarScreenState();
}

class _BarScreenState extends State<BarScreen> {
  bool _going = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.bgBase,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 18),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.bgSurface, AppColors.bgBase],
                  ),
                ),
                child: const Center(child: Text('🍸', style: TextStyle(fontSize: 80))),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.venueId, style: AppTextStyles.h1),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star, color: AppColors.warning, size: 14),
                          Text(' 4.7 · Night Club',
                            style: AppTextStyles.bodyXs),
                        ]),
                      ],
                    )),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Open',
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // Check-in count
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(children: [
                      const Icon(Icons.people_outline,
                        color: AppColors.accentStart, size: 20),
                      const SizedBox(width: 10),
                      Text('47 people here now',
                        style: AppTextStyles.bodyMd),
                      const Spacer(),
                      Text('LIVE', style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.accentStart)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // Info rows
                  _InfoRow(icon: Icons.location_on_outlined, label: 'Сүхбаатар дүүрэг, УБ'),
                  _InfoRow(icon: Icons.access_time, label: '21:00 – 05:00 · Өнөөдөр нээлттэй'),
                  _InfoRow(icon: Icons.phone_outlined, label: '+976 9911 2233'),
                  const SizedBox(height: 20),
                  // Today event
                  Text("TODAY'S EVENT", style: AppTextStyles.labelSm),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: AppColors.accentGradientSoft,
                        ),
                        child: const Center(child: Text('🎧', style: TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DJ Bayar · Live Set', style: AppTextStyles.h3),
                          Text('23:00 · Free entry before midnight',
                            style: AppTextStyles.bodyXs),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(children: [
                    Expanded(
                      child: GradientButton(
                        label: _going ? 'Going ✓' : 'Going',
                        onPressed: () => setState(() => _going = !_going),
                        height: 46,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label: const Text('Directions'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          side: const BorderSide(color: AppColors.hairline2),
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label;
  const _InfoRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Icon(icon, color: AppColors.textSecondary, size: 18),
      const SizedBox(width: 10),
      Text(label, style: AppTextStyles.bodyMd),
    ]),
  );
}
