import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class AffiliateScreen extends StatelessWidget {
  final bool unlockMode;
  const AffiliateScreen({super.key, this.unlockMode = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    appBar: AppBar(
      backgroundColor: AppColors.bgBase,
      leading: IconButton(onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
      title: Text('Affiliate Program', style: AppTextStyles.h2),
    ),
    body: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🦉', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 24),
        Text('Earn with Night Owl', style: AppTextStyles.displaySm,
          textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Refer venues and earn commission for every subscription.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary, height: 1.5),
          textAlign: TextAlign.center),
        const SizedBox(height: 40),
        GradientButton(
          label: unlockMode ? 'Unlock Affiliate Access' : 'Share Your Link',
          onPressed: () async {
            final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
            final ref = uid.length >= 8 ? uid.substring(0, 8) : uid;
            final link = 'https://nightowl.ub/join?ref=$ref';
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(unlockMode
                  ? 'Урилгын холбоос хуулагдлаа: $link'
                  : 'Холбоос хуулагдлаа 🔗 $link'),
                duration: const Duration(seconds: 3)));
            }
          },
        ),
      ]),
    ),
  );
}
