import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/settings_rows.dart';
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
              padding: const EdgeInsets.all(AppSpacing.page),
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
                _pendingReports(),
                // Settings rhythm (settings_rows kit): 28 between sections,
                // 12 from a label to its card.
                const SizedBox(height: 28),
                const SettingsSectionLabel('Удирдлага'),
                const SizedBox(height: AppSpacing.x3),
                SettingsCard(children: [
                  _navigation(Icons.people_outline, 'Хэрэглэгчид',
                      'Хайх, баталгаажуулах, хориг удирдах', '/admin/users'),
                  const SettingsDivider(),
                  _navigation(Icons.article_outlined, 'Контент',
                      'Нийтлэл болон сэтгэгдлийг шалгах', '/admin/content'),
                  const SettingsDivider(),
                  _navigation(
                      Icons.history_rounded,
                      'Үйлдлийн түүх',
                      'Хэн, хэзээ, ямар үндэслэлээр өөрчилснийг харах',
                      '/admin/audit'),
                ]),
                const SizedBox(height: 28),
                const SettingsSectionLabel('Аппын тойм'),
                const SizedBox(height: AppSpacing.x3),
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
                      ('comments', 'Сэтгэгдэл', AppIcons.comment),
                      ('venues', 'Газар', AppIcons.venue),
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
                                const SizedBox(height: AppSpacing.x1),
                                Text(item.$2, style: AppTextStyles.bodyMd)
                              ])))
                  ]);
                }),
                const SizedBox(height: 28),
                const SettingsSectionLabel('Хөтөлбөрүүд'),
                const SizedBox(height: AppSpacing.x3),
                SettingsCard(children: [
                  _navigation(Icons.auto_awesome_outlined, 'Онцгой эвентүүд',
                      'Онцлох эвентүүдийг сонгох', '/admin/featured-events'),
                  const SettingsDivider(),
                  _navigation(Icons.insights_outlined, 'Эхний туршилт',
                      'Creator, газар, контент ба үр дүн', '/admin/pilot'),
                ]),
                const SizedBox(height: AppSpacing.x4),
              ])));

  Widget _navigation(
          IconData icon, String title, String subtitle, String route) =>
      SettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: () => context.push(route));

  /// Reports waiting for a decision: a tinted card above the grouped rows.
  /// It holds one kit row behind the same 6 px inset as [SettingsCard], so
  /// its icon tile, text and chevron line up with the rows below at every
  /// width (the tile hides with theirs on narrow screens with large text).
  Widget _pendingReports() => Material(
      color: AppColors.silver.withValues(alpha: .1),
      borderRadius: AppRadii.lgR,
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.all(6),
          child: SettingsRow(
              icon: Icons.flag_outlined,
              title: 'Шалгах мэдээлэл',
              subtitle:
                  '${_summary.counts['pending_reports']} мэдээлэл шийдвэр хүлээж байна',
              onTap: () => context.push('/admin/reports'))));
}
