import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../discovery/services/discovery_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../services/block_report_service.dart';
import '../services/report_submission_service.dart';
import '../../post/services/content_publication.dart';

const _reasons = <String, String>{
  'spam': 'Спам / хуурамч',
  'harassment': 'Дарамт / доромжлол',
  'nudity': 'Бэлгийн агуулга',
  'violence': 'Хүчирхийлэл',
  'hate': 'Үзэн ядалт',
  'other': 'Бусад',
};

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

void _blockChanged(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(socialVersionProvider.notifier).state++;
  container.invalidate(blockedIdsProvider);
}

Future<void> _blockWithConfirmation(BuildContext context,
    {required BlockMutationService service,
    required PublicationSession session,
    required String userId,
    required String username,
    VoidCallback? onBlocked}) async {
  try {
    session.check();
    final confirmed = await _confirmBlock(context, username);
    if (confirmed != true || !context.mounted) return;
    session.check();
    await service.setBlocked(session, userId, blocked: true);
    if (!context.mounted || !session.isCurrent) return;
    _blockChanged(context);
    _toast(context, '@$username блоклогдлоо');
    onBlocked?.call();
  } catch (error) {
    if (context.mounted) {
      _toast(
          context,
          error is PublicationFailure
              ? error.message
              : 'Блоклож чадсангүй. Дахин оролдоно уу.');
    }
  }
}

/// The selected target is reviewed under the account that opened this form.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? title,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _ReportForm(targetType: targetType, targetId: targetId, title: title),
  );
  if (sent == true && context.mounted) {
    _toast(context, 'Мэдээлэл хүлээн авлаа. Модератор шалгана.');
  }
}

class _ReportForm extends ConsumerStatefulWidget {
  final String targetType, targetId;
  final String? title;
  const _ReportForm(
      {required this.targetType, required this.targetId, this.title});
  @override
  ConsumerState<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends ConsumerState<_ReportForm> {
  late final ReportSubmissionService _service;
  late final PublicationSession _session;
  final _details = TextEditingController();
  String? _reason, _error;
  bool _busy = false, _stale = false;
  StreamSubscription<void>? _auth;
  @override
  void initState() {
    super.initState();
    _service = ref.read(reportSubmissionServiceProvider);
    _session = _service.captureSession();
    _auth = _service.sessionChanges.listen((_) {
      if (!_session.isCurrent) _invalidate();
    }, onError: (Object _) => _invalidate());
  }

  @override
  void dispose() {
    _auth?.cancel();
    _session.close();
    _details.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (!mounted || _stale) return;
    _details.clear();
    setState(() {
      _stale = true;
      _reason = null;
      _error =
          'Нэвтрэх хаяг өөрчлөгдсөн байна. Мэдээлэх цонхоо дахин нээнэ үү.';
    });
  }

  Future<void> _submit() async {
    if (_busy || _stale || _reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.submit(_session,
          targetType: widget.targetType,
          targetId: widget.targetId,
          reason: _reason!,
          details: _details.text);
      if (mounted && _session.isCurrent) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is PublicationFailure
            ? error.message
            : 'Илгээж чадсангүй. Дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                _stale
                                    ? 'Юунд мэдээлэх вэ?'
                                    : widget.title ?? 'Юунд мэдээлэх вэ?',
                                style: AppTextStyles.h3)),
                        IconButton(
                            tooltip: 'Хаах',
                            onPressed:
                                _busy ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close))
                      ]),
                      if (const {'message', 'group_message'}
                          .contains(widget.targetType))
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                                'Зөвхөн сонгосон мессежийн агуулгыг модераторт илгээнэ. Ярианы бусад мессежийг нээхгүй.')),
                      ..._reasons.entries.map((entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_reason == entry.key
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                          title: Text(entry.value),
                          onTap: _busy || _stale
                              ? null
                              : () => setState(() => _reason = entry.key))),
                      TextField(
                          controller: _details,
                          enabled: !_busy && !_stale,
                          maxLength: 2000,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Нэмэлт тайлбар (сонголтоор)',
                              hintText: 'Юу болсныг товч бичнэ үү')),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: AppColors.error))),
                      FilledButton.icon(
                          onPressed: _reason == null || _busy || _stale
                              ? null
                              : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.flag_outlined),
                          label: Text(
                              _busy ? 'Илгээж байна…' : 'Модераторт илгээх')),
                    ]),
              )),
        ),
      );
}

/// Хэрэглэгчийн "..." options sheet (Block + Report)
Future<void> showUserOptionsSheet(
  BuildContext context, {
  required String userId,
  required String username,
  VoidCallback? onBlocked,
}) async {
  final service = ProviderScope.containerOf(context, listen: false)
      .read(blockMutationServiceProvider);
  final session = service.captureSession();
  Future<void>? blockAction;
  try {
    await showModalBottomSheet(
      context: context,
      // Өндөр агуулга халихаас сэргийлж — scroll + safe area
      // (өнгө, булан, drag handle-ийг theme өгнө)
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.error),
                title: Text('@$username-г блоклох',
                    style:
                        AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
                onTap: () {
                  if (blockAction != null) return;
                  Navigator.of(sheetCtx).pop();
                  blockAction = _blockWithConfirmation(context,
                      service: service,
                      session: session,
                      userId: userId,
                      username: username,
                      onBlocked: onBlocked);
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.flag_outlined, color: AppColors.textSecondary),
                title: Text('Мэдээлэх', style: AppTextStyles.bodyMd),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  showReportSheet(context,
                      targetType: 'user',
                      targetId: userId,
                      title: '@$username-г юунд мэдээлэх вэ?');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    await blockAction;
  } finally {
    session.close();
  }
}

/// Постын "..." options sheet.
/// Өөрийн пост (isOwn) бол Delete, бусдынх бол Report + Block.
Future<void> showPostOptionsSheet(
  BuildContext context, {
  required String postId,
  required String authorId,
  required String authorUsername,
  bool isOwn = false,
  String? currentCaption,
  VoidCallback? onBlocked,
  Future<bool> Function()? onDelete,
  Future<void> Function(String)? onEditCaption,
}) async {
  final service = ProviderScope.containerOf(context, listen: false)
      .read(blockMutationServiceProvider);
  final session = service.captureSession();
  Future<void>? blockAction;
  try {
    await showModalBottomSheet(
      context: context,
      // Өндөр агуулга халихаас сэргийлж — scroll + safe area
      // (өнгө, булан, drag handle-ийг theme өгнө)
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),

              // ── Өөрийн пост: Тайлбар засах + Delete ──
              if (isOwn) ...[
                if (onEditCaption != null)
                  ListTile(
                    leading: Icon(Icons.edit_outlined,
                        color: AppColors.textSecondary),
                    title: Text('Тайлбар засах', style: AppTextStyles.bodyMd),
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      final text = await _editCaptionDialog(
                          context, currentCaption ?? '');
                      if (text != null) {
                        try {
                          await onEditCaption(text);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Хадгалж чадсангүй. Дахин оролдоно уу.')));
                          }
                        }
                      }
                    },
                  ),
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Постыг устгах',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.error)),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final ok = await _confirmDeletePost(context);
                    if (ok != true) return;
                    final deleted = await onDelete?.call() ?? false;
                    if (context.mounted) {
                      _toast(
                          context,
                          deleted
                              ? 'Пост устгагдлаа'
                              : 'Устгаж чадсангүй. Дахин оролдоно уу.');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ] else ...[
                ListTile(
                  leading:
                      Icon(Icons.flag_outlined, color: AppColors.textSecondary),
                  title: Text('Постыг мэдээлэх', style: AppTextStyles.bodyMd),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    showReportSheet(context,
                        targetType: 'post', targetId: postId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: AppColors.error),
                  title: Text('@$authorUsername-г блоклох',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.error)),
                  onTap: () {
                    if (blockAction != null) return;
                    Navigator.of(sheetCtx).pop();
                    blockAction = _blockWithConfirmation(context,
                        service: service,
                        session: session,
                        userId: authorId,
                        username: authorUsername,
                        onBlocked: onBlocked);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
    await blockAction;
  } finally {
    session.close();
  }
}

Future<String?> _editCaptionDialog(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text('Тайлбар засах', style: AppTextStyles.h3),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        maxLength: 300,
        autofocus: true,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        decoration: const InputDecoration(
            hintText: 'Тайлбар...', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text('Болих',
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary))),
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(ctrl.text),
            child: Text('Хадгалах',
                style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.accentStart,
                    fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

Future<bool?> _confirmDeletePost(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text('Постыг устгах уу?', style: AppTextStyles.h3),
      content: Text('Энэ постыг бүрмөсөн устгана. Буцаах боломжгүй.',
          style: AppTextStyles.bodySm
              .copyWith(color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text('Болих',
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary))),
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text('Устгах',
                style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.error, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

Future<bool?> _confirmBlock(BuildContext context, String username) {
  return showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text('@$username-г блоклох уу?', style: AppTextStyles.h3),
      content: Text('Түүний постууд таны feed-д харагдахгүй болно.',
          style: AppTextStyles.bodySm
              .copyWith(color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text('Болих',
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary))),
        TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text('Блоклох',
                style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.error, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}
