import 'package:flutter/material.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/gradient_button.dart';
import '../widgets/invite_sheet.dart';

/// Free invitations have no membership purchase, reward or local access flag.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    // Нэгдсэн толгой (DS-06): pop хийх хуудасгүй бол Тохиргоо руу
    appBar: const AppHeader.title(
        title: 'Найзаа урих', fallbackLocation: AppRoutes.settings),
    body: Center(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.people_outline, size: 56, color: AppColors.silver),
        const SizedBox(height: 24),
        Text('Оройгоо хамт бүтээе', style: AppTextStyles.displaySm,
          textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('Night Owl үнэгүй. Найзуудтайгаа газар нээж, дурсамжаа хуваалцаарай.',
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary, height: 1.6),
          textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GradientButton(label: 'Урилгын холбоос',
          onPressed: () => showInviteSheet(context)),
      ]),
    ))),
  );
}
