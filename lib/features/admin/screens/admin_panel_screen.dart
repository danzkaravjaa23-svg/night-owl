import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';
import '../widgets/admin_gate.dart';
import '../widgets/admin_widgets.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});
  @override
  Widget build(BuildContext context) => const AdminGate(child: _Dashboard());
}

class _Dashboard extends ConsumerStatefulWidget {
  const _Dashboard();
  @override
  ConsumerState<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<_Dashboard> {
  late AdminConsoleSummary _summary;
  bool _loading = false;
  AdminConsoleFailure? _error;
  @override
  void initState() {
    super.initState();
    _summary = ref.read(adminConsoleAccessProvider)!.summary;
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final access = ref.read(adminConsoleAccessProvider)!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await access.service.summary(access.session);
      if (mounted && access.session.isCurrent) {
        setState(() => _summary = summary);
      }
    } catch (error) {
      if (mounted && access.session.isCurrent) {
        setState(() => _error = error is AdminConsoleFailure
            ? error
            : const AdminConsoleFailure('network'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
      title: 'Админ панел',
      onRefresh: _loading ? null : _refresh,
      child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const AdminIntro(
                    title: 'Хамт олноо хамгаалъя',
                    subtitle:
                        'Мэдээллийг шалгаж, хэрэглэгчид болон контентыг нэг дор удирдаарай.'),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  AdminMessage(
                      icon: Icons.cloud_off,
                      title: 'Шинэчилж чадсангүй',
                      message: _error!.message,
                      onRetry: _refresh),
                _navigation(
                    Icons.flag_outlined,
                    'Шалгах мэдээлэл',
                    '${_summary.counts['pending_reports']} мэдээлэл шийдвэр хүлээж байна',
                    '/admin/reports',
                    prominent: true),
                const SizedBox(height: 20),
                Text('Удирдлага', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                _navigation(Icons.people_outline, 'Хэрэглэгчид',
                    'Хайх, баталгаажуулах, хориг удирдах', '/admin/users'),
                _navigation(Icons.article_outlined, 'Контент',
                    'Нийтлэл болон сэтгэгдлийг шалгах', '/admin/content'),
                _navigation(
                    Icons.history_rounded,
                    'Үйлдлийн түүх',
                    'Хэн, хэзээ, ямар үндэслэлээр өөрчилснийг харах',
                    '/admin/audit'),
                const SizedBox(height: 24),
                Text('Аппын тойм', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth > 650
                      ? 3
                      : MediaQuery.textScalerOf(context).scale(14) > 20
                          ? 1
                          : 2;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final item in const [
                      ('users', 'Хэрэглэгч', Icons.people_outline),
                      ('posts', 'Нийтлэл', Icons.grid_view_rounded),
                      ('comments', 'Сэтгэгдэл', Icons.chat_bubble_outline),
                      ('venues', 'Газар', Icons.place_outlined),
                      ('events', 'Эвент', Icons.event_outlined),
                      ('banned_users', 'Хориглосон', Icons.block_rounded),
                    ])
                      SizedBox(
                          width: width,
                          child: AdminCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Icon(item.$3,
                                    size: 22, color: AppColors.silver),
                                const SizedBox(height: 14),
                                Text('${_summary.counts[item.$1]}',
                                    style: AppTextStyles.h1),
                                const SizedBox(height: 4),
                                Text(item.$2, style: AppTextStyles.bodyMd)
                              ])))
                  ]);
                }),
                const SizedBox(height: 28),
                Text('Хөтөлбөрүүд', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                _navigation(Icons.auto_awesome_outlined, 'Онцгой эвентүүд',
                    'Онцлох эвентүүдийг сонгох', '/admin/featured-events'),
                _navigation(Icons.insights_outlined, 'Эхний туршилт',
                    'Creator, газар, контент ба үр дүн', '/admin/pilot'),
                const SizedBox(height: 16),
              ])));

  Widget _navigation(IconData icon, String title, String subtitle, String route,
          {bool prominent = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
              color: prominent
                  ? AppColors.silver.withValues(alpha: .1)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: () => context.push(route),
                  child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(children: [
                        Icon(icon, color: AppColors.silver, size: 24),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(title, style: AppTextStyles.labelLg),
                              const SizedBox(height: 5),
                              Text(subtitle,
                                  style: AppTextStyles.bodySm
                                      .copyWith(height: 1.4))
                            ])),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded,
                            color: AppColors.textTertiary)
                      ])))));
}
