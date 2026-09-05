import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../utils/app_links.dart';

/// Найзаа урих — урилгын холбоос хуваалцах/хуулах bottom sheet
Future<void> showInviteSheet(BuildContext context) async {
  final uid = SupabaseService.currentUser?.id ?? '';
  final ref = uid.length >= 8 ? uid.substring(0, 8) : uid;
  final link = inviteLink(ref);
  const msg = '🦉 Night Owl UB — Улаанбаатарын шөнийн амьдралын апп. '
      'Над дээр нэгдээрэй!';

  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppColors.hairline2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('🦉', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text('Найзаа урих', style: AppTextStyles.h2),
          const SizedBox(height: 6),
          Text('Урилгын холбоосоо найзууддаа илгээгээрэй',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          // Холбоос
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              const Icon(Icons.link, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(child: Text(link,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary))),
            ]),
          ),
          const SizedBox(height: 16),

          // Хуваалцах
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Share.share('$msg\n$link', subject: 'Night Owl UB');
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Холбоос хуулагдлаа 🔗')));
                }
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('Хуваалцах',
                style: AppTextStyles.btn.copyWith(color: Colors.white))),
            ),
          )),
          const SizedBox(height: 10),

          // Холбоос хуулах
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Холбоос хуулагдлаа 🔗')));
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline)),
              child: Center(child: Text('Холбоос хуулах',
                style: AppTextStyles.btn.copyWith(color: AppColors.textPrimary))),
            ),
          )),
        ]),
      ),
    ),
  );
}
