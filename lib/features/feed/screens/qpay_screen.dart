import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

/// QPay төлбөрийн дэлгэц.
/// ⚠️ QPay merchant холболт хараахан хийгдээгүй — энэ дэлгэц одоогоор
/// зөвхөн урьдчилсан UI. Хуурамч unlock хийхгүй (өмнө 2сек delay-ээр
/// үнэгүй нээдэг байсныг хаасан). Интеграци орж ирэхэд amount-ыг
/// route extra эсвэл DB-ээс дамжуулна.
class QPayScreen extends StatelessWidget {
  final String contentId;
  /// Төлбөрийн дүн (₮). Хатуу бичихгүй — route/DB-ээс ирэхэд харуулна.
  final int? amount;
  const QPayScreen({super.key, required this.contentId, this.amount});

  String get _amountLabel {
    final a = amount;
    if (a == null) return '';
    // ₮5000 → ₮5,000
    final s = a.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₮$buf';
  }

  void _pay(BuildContext context) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Төлбөрийн систем', style: AppTextStyles.h3),
        content: Text(
          'QPay төлбөрийн холболт удахгүй идэвхжинэ. Одоогоор төлбөр '
          'хийх боломжгүй байна.',
          style: AppTextStyles.bodySm.copyWith(
            color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text('Ойлголоо', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.accentStart))),
        ],
      ),
    );
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
        title: Text('QPAY · ТӨЛБӨР', style: AppTextStyles.mono),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
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
            if (amount != null) ...[
              Text(_amountLabel, style: AppTextStyles.displayMd),
              const SizedBox(height: 8),
            ] else ...[
              Text('Түгжээтэй контент', style: AppTextStyles.h2),
              const SizedBox(height: 8),
            ],
            // Юу ч poll хийдэггүй тул "хүлээж байна" гэж хуурахгүй
            Text('Төлбөрийн систем удахгүй нээгдэнэ',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
            const SizedBox(height: 40),
            const Divider(color: AppColors.hairline),
            const SizedBox(height: 20),
            Text('ЭСВЭЛ БАНКАА СОНГО', style: AppTextStyles.labelSm),
            const SizedBox(height: 16),
            const _BankRow(),
            const Spacer(),
            GradientButton(
              label: amount != null ? 'Төлөх $_amountLabel' : 'Төлбөр хийх',
              onPressed: () => _pay(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Банкны сонголт — интеграци ороогүй тул идэвхгүй харагдацтай
class _BankRow extends StatelessWidget {
  const _BankRow();

  @override
  Widget build(BuildContext context) {
    const banks = ['Khan', 'Golomt', 'TDB', 'Xac'];
    return Column(children: [
      Opacity(
        opacity: 0.4,
        child: Row(
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
        ),
      ),
      const SizedBox(height: 8),
      Text('Удахгүй нээгдэнэ',
          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary)),
    ]);
  }
}
