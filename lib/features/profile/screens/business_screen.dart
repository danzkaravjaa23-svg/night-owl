import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';

class BusinessScreen extends ConsumerStatefulWidget {
  const BusinessScreen({super.key});
  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends ConsumerState<BusinessScreen> {
  bool _busy = false;

  Future<void> _becomeBusiness() async {
    if (_busy) return;
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('profiles')
          .update({'is_business': true}).eq('id', me);
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Бизнес аккаунт идэвхжлээ ✓'),
          behavior: SnackBarBehavior.floating));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Идэвхжүүлж чадсангүй. Дахин оролдоно уу'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusiness = ref.watch(currentProfileProvider).maybeWhen(
      data: (p) => p?.isBusiness ?? false,
      orElse: () => false,
    );
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Бизнес самбар', style: AppTextStyles.h2),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // ── Бизнес болох / идэвхтэй төлөв ──
        _BecomeBusinessCard(
          isBusiness: isBusiness,
          busy: _busy,
          onTap: _becomeBusiness,
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

        // ── Аналитик (жишээ дата — жинхэнэ эх сурвалж хараахан алга) ──
        Row(children: [
          Text('СТАТИСТИК', style: AppTextStyles.labelSm),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Жишээ дата', style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textTertiary, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 12),
        const Row(children: [
          _StatCard(label: 'Үзэлт', value: '3,421', delta: '+12%'),
          SizedBox(width: 12),
          _StatCard(label: 'Check-in', value: '142', delta: '+8%'),
          SizedBox(width: 12),
          _StatCard(label: 'Үнэлгээ', value: '4.7', delta: '★'),
        ]),
        const SizedBox(height: 24),
        Text('ҮЗЭЛТ · 7 ХОНОГ', style: AppTextStyles.labelSm),
        const SizedBox(height: 12),
        // Simple bar chart (жишээ)
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
        Text('УДИРДЛАГА', style: AppTextStyles.labelSm),
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
        )),
        const SizedBox(height: 24),
        GradientButton(label: 'Эвент нэмэх',
          onPressed: () => context.push(AppRoutes.createEvent)),
      ]),
    );
  }
}

/// Бизнес болох CTA — аль хэдийн бизнес бол "Идэвхтэй ✓" төлөв, ачаалахад spinner
class _BecomeBusinessCard extends StatelessWidget {
  final bool isBusiness;
  final bool busy;
  final VoidCallback onTap;
  const _BecomeBusinessCard({
    required this.isBusiness, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isBusiness ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isBusiness ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isBusiness ? 'Бизнес аккаунт' : 'Бизнес аккаунт болох',
                style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
              const SizedBox(height: 2),
              Text(isBusiness
                  ? 'Live хийх, эвент зарлах боломжтой'
                  : 'Live хийх, эвент зарлах, дагуулагч цуглуулах',
                style: AppTextStyles.bodyXs.copyWith(color: Colors.white70)),
            ])),
            if (busy)
              const SizedBox(width: 22, height: 22, child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            else if (isBusiness)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Идэвхтэй ✓', style: AppTextStyles.bodyXs.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
    );
  }
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

class _ActionTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.onTap);
  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline)),
          child: Column(children: [
            Icon(widget.icon, color: AppColors.accentStart, size: 24),
            const SizedBox(height: 6),
            Text(widget.label, style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textPrimary)),
          ]),
        ),
      ),
    ),
  );
}
