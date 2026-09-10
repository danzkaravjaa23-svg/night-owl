import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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

/// Report шалтгаан сонгох sheet
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? title,
}) async {
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
          Text(title ?? 'Юунд мэдээлэх вэ?', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          ..._reasons.entries.map((e) => ListTile(
            title: Text(e.value, style: AppTextStyles.bodyMd),
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
                  ? 'Мэдээлэл хүлээн авлаа. Баярлалаа 🙏'
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
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              final ok = await _confirmBlock(context, username);
              if (ok != true) return;
              final err = await BlockReportService.block(userId);
              if (context.mounted) {
                _toast(context, err == null
                  ? '@$username блоклогдлоо' : 'Алдаа: $err');
              }
              if (err == null) onBlocked?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
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
  Future<void> Function()? onDelete,
  Future<void> Function(String)? onEditCaption,
}) async {
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
                leading: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                title: Text('Тайлбар засах', style: AppTextStyles.bodyMd),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  final text = await _editCaptionDialog(context, currentCaption ?? '');
                  if (text != null) await onEditCaption(text);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Постыг устгах',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                final ok = await _confirmDeletePost(context);
                if (ok != true) return;
                await onDelete?.call();
                if (context.mounted) _toast(context, 'Пост устгагдлаа');
              },
            ),
            const SizedBox(height: 12),
          ] else ...[
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
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
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              final ok = await _confirmBlock(context, authorUsername);
              if (ok != true) return;
              final err = await BlockReportService.block(authorId);
              if (context.mounted) {
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
      title: Text('Нэмэлт тайлбар', style: AppTextStyles.h3),
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
            color: AppColors.accentStart, fontWeight: FontWeight.w600))),
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
      title: Text('Тайлбар засах', style: AppTextStyles.h3),
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
            color: AppColors.accentStart, fontWeight: FontWeight.w600))),
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
      content: Text(
        'Энэ постыг бүрмөсөн устгана. Буцаах боломжгүй.',
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(false),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(true),
          child: Text('Устгах', style: AppTextStyles.bodyMd.copyWith(
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
      content: Text(
        'Блоклосон хүн таны пост, профайлыг харахаа болино. Та хоёр бие биенээ хайж олохгүй.',
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(false),
          child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary))),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(true),
          child: Text('Блоклох', style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.error, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}
