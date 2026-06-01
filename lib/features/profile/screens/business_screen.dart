import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';

class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key});

  Future<void> _becomeBusiness(BuildContext context) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      await SupabaseService.client.from('profiles')
          .update({'is_business': true}).eq('id', me);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Бизнес аккаунт идэвхжлээ ✓'),
          behavior: SnackBarBehavior.floating));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    appBar: AppBar(
      backgroundColor: AppColors.bgBase,
      leading: IconButton(onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
      title: Text('Business Dashboard', style: AppTextStyles.h2),
    ),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      // ── Бизнес болох + хурдан үйлдэл ──
      GestureDetector(
        onTap: () => _becomeBusiness(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Бизнес аккаунт болох', style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
              const SizedBox(height: 2),
              Text('Live хийх, эвент зарлах, дагуулагч цуглуулах',
                style: AppTextStyles.bodyXs.copyWith(color: Colors.white70)),
            ])),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _ActionTile('Эвент нэмэх', Icons.event_rounded,
          () => context.push(AppRoutes.createEvent))),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile('Live эхлүүлэх', Icons.sensors_rounded,
          () => context.push(AppRoutes.goLive))),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile('Газраа удирдах', Icons.storefront_outlined,
          () => context.push(AppRoutes.venueEdit))),
      ]),
      const SizedBox(height: 24),

      // Stats row
      Row(children: [
        _StatCard(label: 'Views', value: '3,421', delta: '+12%'),
        const SizedBox(width: 12),
        _StatCard(label: 'Check-ins', value: '142', delta: '+8%'),
        const SizedBox(width: 12),
        _StatCard(label: 'Rating', value: '4.7', delta: '★'),
      ]),
      const SizedBox(height: 24),
      Text('VIEWS · 7 DAYS', style: AppTextStyles.labelSm),
      const SizedBox(height: 12),
      // Simple bar chart
      SizedBox(height: 80,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [42, 65, 48, 78, 90, 55, 88].map((v) =>
            Container(
              width: 28,
              height: v.toDouble(),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          ).toList(),
        ),
      ),
      const SizedBox(height: 24),
      Text('MANAGEMENT', style: AppTextStyles.labelSm),
      const SizedBox(height: 12),
      ...[
        ('Хаяг & байршил', Icons.location_on_outlined),
        ('Ажиллах цаг', Icons.access_time),
        ('Зураг / cover', Icons.photo_library_outlined),
        ('Холбоо барих утас', Icons.phone_outlined),
      ].map((r) => ListTile(
        leading: Icon(r.$2, color: AppColors.textSecondary),
        title: Text(r.$1, style: AppTextStyles.bodyMd),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        onTap: () => context.push(AppRoutes.venueEdit),
      )).toList(),
      const SizedBox(height: 24),
      GradientButton(label: 'Эвент нэмэх',
        onPressed: () => context.push(AppRoutes.createEvent)),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value, delta;
  const _StatCard({required this.label, required this.value, required this.delta});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.bodyXs),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.h2),
        Text(delta, style: AppTextStyles.bodyXs.copyWith(
          color: AppColors.success)),
      ]),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline)),
      child: Column(children: [
        Icon(icon, color: AppColors.accentStart, size: 24),
        const SizedBox(height: 6),
        Text(label, style: AppTextStyles.bodyXs.copyWith(color: AppColors.textPrimary)),
      ]),
    ),
  );
}
