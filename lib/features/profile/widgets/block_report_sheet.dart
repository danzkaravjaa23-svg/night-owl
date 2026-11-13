import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../discovery/services/discovery_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_sheet.dart';
import '../services/block_report_service.dart';

const _reasons = <String, String>{
  'spam':       'Спам / хуурамч',
  'harassment': 'Дарамт / доромжлол',
  'nudity':     'Бэлгийн агуулга',
  'violence':   'Хүчирхийлэл',
  'hate':       'Үзэн ядалт',
  'other':      'Бусад',
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

/// Report шалтгаан сонгох sheet.
///
/// Sheet нь root navigator дээр (showAppSheet, DS-02): sheet-ийг зөвхөн
/// `sheetCtx`-оор хаана; диалог ба toast нь [context]-оор, sheet хаагдсаны
/// дараа. [dark] — зөвхөн хуучин дэвсгэр нь заавал харанхуй байсан sheet-д
/// (docs/DESIGN_SYSTEM.md §4). Reels-ээс нээх report sheet апп-ын theme-ийг
/// зориуд дагана.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? title,
  bool dark = false,
}) async {
  await showAppSheet<void>(
    context: context,
    dark: dark,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetHeader(title: title ?? 'Юунд мэдээлэх вэ?'),
          ..._reasons.entries.map((e) => ListTile(
            // Гарчигтай (AppSheetHeader, 20 px) ижил ирмэг дээр эхэлнэ.
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            // Adaptive AppTextStyles нь апп-ын горимыг дагадаг тул харанхуй
            // sheet-д .onDark хувилбарыг өгнө.
            title: Text(e.value, style: dark
                ? AppTextStyles.bodyMd.onDark : AppTextStyles.bodyMd),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              // 'Бусад' сонговол нэмэлт тайлбар (details) авна — модерацид хэрэгтэй
              String? details;
              if (e.key == 'other') {
                if (!context.mounted) return;
                details = await _detailsDialog(context);
                if (details == null) return; // цуцалсан
              }
              if (context.mounted) {
                _toast(context, 'Илгээж байна...');
              }
              final err = await BlockReportService.report(
                targetType: targetType, targetId: targetId,
                reason: e.key, details: details);
              if (context.mounted) {
                _toast(context, err == null
                  ? 'Мэдээлэл хүлээн авлаа. Баярлалаа'
                  : 'Алдаа: $err');
              }
            },
          )),
          const SizedBox(height: 12),
        ],
      ),
      ),
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
  // Өнгө, булан, drag handle, scroll/safe area-г showAppSheet + theme өгнө.
  await showAppSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          ListTile(
            leading: Icon(Icons.block, color: AppColors.danger),
            title: Text('@$username-г блоклох',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.danger)),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              final ok = await _confirmBlock(context, username);
              if (ok != true) return;
              final err = await BlockReportService.block(userId);
              if (context.mounted) {
                if (err == null) _blockChanged(context);
                _toast(context, err == null
                  ? '@$username блоклогдлоо' : 'Алдаа: $err');
              }
              if (err == null) onBlocked?.call();
            },
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined, color: AppColors.textSecondary),
            title: Text('Мэдээлэх', style: AppTextStyles.bodyMd),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              showReportSheet(context,
                targetType: 'user', targetId: userId,
                title: '@$username-г юунд мэдээлэх вэ?');
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
      ),
    ),
  );
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
  // Өнгө, булан, drag handle, scroll/safe area-г showAppSheet + theme өгнө.
  await showAppSheet<void>(
    context: context,
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
                leading: Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                title: Text('Тайлбар засах', style: AppTextStyles.bodyMd),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final text = await _editCaptionDialog(context, currentCaption ?? '');
                  if (text != null) {
                    try { await onEditCaption(text); }
                    catch (_) {
                      if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Хадгалж чадсангүй. Дахин оролдоно уу.'))); }
                    }
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text('Постыг устгах',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.danger)),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                final ok = await _confirmDeletePost(context);
                if (ok != true) return;
                final deleted = await onDelete?.call() ?? false;
                if (context.mounted) _toast(context, deleted ? 'Пост устгагдлаа' : 'Устгаж чадсангүй. Дахин оролдоно уу.');
              },
            ),
            const SizedBox(height: 12),
          ] else ...[
          ListTile(
            leading: Icon(Icons.flag_outlined, color: AppColors.textSecondary),
            title: Text('Постыг мэдээлэх', style: AppTextStyles.bodyMd),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              showReportSheet(context,
                targetType: 'post', targetId: postId);
            },
          ),
          ListTile(
            leading: Icon(Icons.block, color: AppColors.danger),
            title: Text('@$authorUsername-г блоклох',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.danger)),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              final ok = await _confirmBlock(context, authorUsername);
              if (ok != true) return;
              final err = await BlockReportService.block(authorId);
              if (context.mounted) {
                if (err == null) _blockChanged(context);
                _toast(context, err == null
                  ? '@$authorUsername блоклогдлоо' : 'Алдаа: $err');
              }
              if (err == null) onBlocked?.call();
            },
          ),
          const SizedBox(height: 12),
          ],
        ],
      ),
      ),
    ),
  );
}

/// 'Бусад' шалтгаанд нэмэлт тайлбар авах диалог.
/// Цуцалбал null, оруулбал (хоосон ч байж болно) тайлбар текстийг буцаана.
Future<String?> _detailsDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('Нэмэлт тайлбар'),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        maxLength: 300,
        autofocus: true,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Юу болсныг товч бичнэ үү (заавал биш)...',
          border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(ctrl.text.trim()),
          child: Text('Илгээх', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.accentText, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

Future<String?> _editCaptionDialog(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('Тайлбар засах'),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        maxLength: 300,
        autofocus: true,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Тайлбар...',
          border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(ctrl.text),
          child: Text('Хадгалах', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.accentText, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

Future<bool?> _confirmDeletePost(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('Постыг устгах уу?'),
      content: Text(
        'Энэ постыг бүрмөсөн устгана. Буцаах боломжгүй.',
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(false),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        // Устгах баталгаа — dangerFill дээр цагаан (DS-03)
        FilledButton(
          onPressed: () => Navigator.of(dCtx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.dangerFill,
            foregroundColor: Colors.white),
          child: const Text('Устгах')),
      ],
    ),
  );
}

Future<bool?> _confirmBlock(BuildContext context, String username) {
  return showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text('@$username-г блоклох уу?'),
      content: Text(
        'Түүний постууд таны feed-д харагдахгүй болно.',
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(false),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        // Блоклох баталгаа — dangerFill дээр цагаан (DS-03)
        FilledButton(
          onPressed: () => Navigator.of(dCtx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.dangerFill,
            foregroundColor: Colors.white),
          child: const Text('Блоклох')),
      ],
    ),
  );
}
