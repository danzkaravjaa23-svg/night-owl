import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class QPayScreen extends StatefulWidget {
  final String contentId;
  const QPayScreen({super.key, required this.contentId});

  @override
  State<QPayScreen> createState() => _QPayScreenState();
}

class _QPayScreenState extends State<QPayScreen> {
  bool _paid = false;
  bool _loading = false;

  Future<void> _pay() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() { _loading = false; _paid = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('QPAY · PAYMENT', style: AppTextStyles.mono),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: _paid ? _SuccessView() : Column(
          children: [
            const Spacer(),
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Center(child: Text('QR', style: TextStyle(
                color: AppColors.textTertiary, fontSize: 28, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 24),
            Text('₮5,000', style: AppTextStyles.displayMd),
            const SizedBox(height: 8),
            Text('Waiting for payment confirmation...',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
            const SizedBox(height: 40),
            const Divider(color: AppColors.hairline),
            const SizedBox(height: 20),
            Text('OR SELECT YOUR BANK', style: AppTextStyles.labelSm),
            const SizedBox(height: 16),
            _BankRow(),
            const Spacer(),
            GradientButton(
              label: _loading ? 'Processing...' : 'Pay ₮5,000',
              onPressed: _loading ? null : _pay,
            ),
          ],
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const banks = ['Khan', 'Golomt', 'TDB', 'Xac'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: banks.map((b) => Container(
        width: 60, height: 44,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Center(child: Text(b, style: AppTextStyles.bodyXs)),
      )).toList(),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success.withOpacity(0.15),
          ),
          child: const Icon(Icons.check_circle_outline,
            color: AppColors.success, size: 48),
        ),
        const SizedBox(height: 24),
        Text('Content Unlocked!', style: AppTextStyles.h1),
        const SizedBox(height: 40),
        GradientButton(label: 'Start Watching', onPressed: () => context.pop()),
      ],
    );
  }
}
