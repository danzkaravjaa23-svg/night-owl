import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/web_share.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../utils/app_links.dart';

/// Найзаа урих — урилгын холбоос хуваалцах/хуулах bottom sheet.
/// Root navigator дээр (showAppSheet): sheet-ийг `sheetCtx`-оор хааж, snackbar-ыг
/// [context]-оор sheet хаагдсаны дараа харуулна.
Future<void> showInviteSheet(BuildContext context) async {
  final uid = SupabaseService.currentUser?.id ?? '';
  final ref = uid.length >= 8 ? uid.substring(0, 8) : uid;
  final link = inviteLink(ref);
  // Бусад апп руу илгээх хэрэглэгчийн текст — emoji нь контент тул хэвээр.
  const msg = '🦉 Night Owl UB — Улаанбаатарын шөнийн амьдралын апп. '
      'Над дээр нэгдээрэй!';

  await showAppSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          // Бариулыг theme (showDragHandle) зурна — энд дахин зурахгүй.
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const NightOwlMark(size: 44),
            const SizedBox(height: 12),
            Text('Найзаа урих', style: AppTextStyles.h2),
            const SizedBox(height: 6),
            Text('Урилгын холбоосоо найзууддаа илгээгээрэй',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),

            // Холбоос
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline)),
              child: Row(children: [
                Icon(Icons.link,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(link,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.textPrimary))),
              ]),
            ),
            const SizedBox(height: 16),

            // Хуваалцах — primary (DS-03)
            GradientButton(
              label: 'Хуваалцах',
              icon: Icon(AppIcons.share),
              onPressed: () async {
                // Tap дотор синхрон шалгана (web share-д шаардлагатай)
                final supported = !kIsWeb || webShareSupported();
                Navigator.of(sheetCtx).pop();
                Future<void> copyLink() async {
                  try {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Холбоос хуулагдлаа')));
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Хуулж чадсангүй — $link')));
                    }
                  }
                }

                // Web Share API-гүй browser (desktop Firefox г.м) —
                // share_plus mailto: нээхээс сэргийлж шууд хуулна
                if (!supported) {
                  await copyLink();
                  return;
                }
                try {
                  await Share.share('$msg\n$link', subject: 'Night Owl UB');
                } catch (_) {
                  await copyLink();
                }
              },
            ),
            const SizedBox(height: 10),

            // Холбоос хуулах — secondary
            OutlineButton(
              label: 'Холбоос хуулах',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Холбоос хуулагдлаа')));
                }
              },
            ),
          ]),
        ),
      ),
    ),
  );
}
