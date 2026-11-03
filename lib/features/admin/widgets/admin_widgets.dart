import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';

class AdminScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onRefresh;
  const AdminScaffold(
      {super.key, required this.title, required this.child, this.onRefresh});

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 25
              ? MediaQuery.textScalerOf(context).scale(24) * 2.3 + 12
              : 64,
          leading: IconButton(
              tooltip: 'Буцах',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/profile');
                }
              }),
          title: Text(title,
              maxLines: 2, style: AppTextStyles.h2.copyWith(height: 1.15)),
          actions: [
            if (onRefresh != null)
              IconButton(
                  tooltip: 'Шинэчлэх',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded))
          ]),
      body: SafeArea(
          top: false,
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: child))));
}

class AdminIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  const AdminIntro({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.h1),
        const SizedBox(height: 8),
        Text(subtitle, style: AppTextStyles.bodyMd.copyWith(height: 1.5)),
        const SizedBox(height: 24)
      ]);
}

class AdminCard extends StatelessWidget {
  final Widget child;
  const AdminCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.bgElevated, borderRadius: BorderRadius.circular(20)),
      child: child);
}

class AdminLoading extends StatelessWidget {
  final String message;
  const AdminLoading({super.key, this.message = 'Мэдээллийг уншиж байна…'});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(height: 16),
        Text(message, style: AppTextStyles.bodyMd, textAlign: TextAlign.center)
      ]));
}

class AdminMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  const AdminMessage(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.onRetry});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 36, color: AppColors.silver),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: AppTextStyles.h2),
        const SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(height: 1.5)),
        if (onRetry != null) ...[
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Дахин оролдох'))
        ]
      ]));
}

class AdminTag extends StatelessWidget {
  final String label;
  final bool warning;
  const AdminTag(this.label, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: (warning ? AppColors.error : AppColors.silver)
              .withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: AppTextStyles.labelMd
              .copyWith(color: warning ? AppColors.error : AppColors.silver)));
}

String adminText(Map<String, dynamic> row, String field,
        [String fallback = '']) =>
    row[field] is String && (row[field] as String).trim().isNotEmpty
        ? (row[field] as String).trim()
        : fallback;

String adminDate(dynamic value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  if (date == null) return 'Огноо тодорхойгүй';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)} · ${two(date.hour)}:${two(date.minute)}';
}

String adminActionLabel(String action) => switch (action) {
      'ban_user' => 'Хэрэглэгчийг хориглох',
      'unban_user' => 'Хоригийг цуцлах',
      'verify_user' => 'Баталгаажуулах',
      'unverify_user' => 'Баталгаажуулалтыг цуцлах',
      'delete_post' => 'Нийтлэлийг устгах',
      'delete_comment' => 'Сэтгэгдлийг устгах',
      'resolve_report' => 'Шийдвэрлэсэн гэж тэмдэглэх',
      'dismiss_report' => 'Үндэслэлгүй гэж хаах',
      'reopen_report' => 'Дахин нээх',
      _ => action,
    };

Future<bool> showAdminAction(BuildContext context, AdminConsoleAccess access,
    {required String action,
    required String targetId,
    required String targetLabel,
    String? reportId}) async {
  if (!access.session.isCurrent) return false;
  return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _AdminActionDialog(
              access: access,
              action: action,
              targetId: targetId,
              targetLabel: targetLabel,
              reportId: reportId)) ??
      false;
}

class _AdminActionDialog extends StatefulWidget {
  final AdminConsoleAccess access;
  final String action, targetId, targetLabel;
  final String? reportId;
  const _AdminActionDialog(
      {required this.access,
      required this.action,
      required this.targetId,
      required this.targetLabel,
      this.reportId});
  @override
  State<_AdminActionDialog> createState() => _AdminActionDialogState();
}

class _AdminActionDialogState extends State<_AdminActionDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  bool _uncertain = false;
  String? _error;
  late final StreamSubscription<AdminConsoleFailure> _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = widget.access.session.invalidations.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  Future<void> _submit() async {
    if (_busy || !widget.access.session.isCurrent) return;
    final reason = _reason.text.trim();
    if (reason.runes.length < 3 || reason.runes.length > 1000) {
      setState(() => _error = const AdminConsoleFailure('reason').message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.access.service.action(widget.access.session,
          action: widget.action,
          targetId: widget.targetId,
          reason: reason,
          reportId: widget.reportId);
      if (mounted && widget.access.session.isCurrent) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted || !widget.access.session.isCurrent) return;
      setState(() {
        _uncertain =
            error is AdminConsoleFailure && error.code == 'action_uncertain';
        _error = error is AdminConsoleFailure
            ? error.message
            : const AdminConsoleFailure('action_uncertain').message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text(adminActionLabel(widget.action), style: AppTextStyles.h2),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.targetLabel, style: AppTextStyles.labelLg),
                    const SizedBox(height: 10),
                    Text(
                        widget.action.startsWith('delete_')
                            ? 'Устгасан контентыг сэргээх боломжгүй. Үйлдэл болон шалтгаан аудитын түүхэнд бүртгэгдэнэ.'
                            : 'Үйлдэл болон шалтгаан аудитын түүхэнд бүртгэгдэнэ.',
                        style: AppTextStyles.bodyMd.copyWith(height: 1.45)),
                    if (widget.reportId != null) ...[
                      const SizedBox(height: 8),
                      Text('Холбоотой мэдээллийг хамт шийдвэрлэнэ.',
                          style: AppTextStyles.bodySm)
                    ],
                    const SizedBox(height: 20),
                    TextField(
                        controller: _reason,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                            labelText: 'Шалтгаан',
                            hintText: 'Шийдвэрийн үндэслэлээ бичнэ үү')),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!,
                              style: AppTextStyles.bodySm
                                  .copyWith(color: AppColors.error)))
                  ]))),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Болих')),
            FilledButton(
                onPressed: _busy || _uncertain ? null : _submit,
                child: Text(_busy ? 'Хадгалж байна…' : 'Баталгаажуулах'))
          ]));
}
