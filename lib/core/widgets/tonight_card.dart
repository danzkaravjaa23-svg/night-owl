import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';

/// Discovery entry remains available even before the first community post.
class TonightCard extends StatelessWidget {
  const TonightCard({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    child: Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.bgElevatedDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairlineDark),
      ),
      child: Stack(children: [
        Positioned.fill(child: Image.asset(
          'assets/images/tonight_city.png', fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              colors: [Color(0xFF17162E), Color(0xFF35305B)]))),
        )),
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xE60B0D17), Color(0x550B0D17)])))),
        Padding(padding: const EdgeInsets.all(22), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('УЛААНБААТАР · AFTER HOURS', style: TextStyle(
              color: AppColors.silverLight, fontSize: 10, letterSpacing: 1.6,
              fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('Чиний орой.\nЧиний хэмнэл.', style: TextStyle(
              fontSize: 29, height: 1.12, letterSpacing: -0.8,
              fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            const Text('Шинэ газар. Шинэ танил. Шинэ дурсамж.',
              style: TextStyle(color: Color(0xFFD1D0E3), fontSize: 12, height: 1.5)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.explore),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: const Color(0xFF242039),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              label: const Text('Газрууд нээх'),
              icon: const Icon(Icons.north_east_rounded, size: 16)),
          ],
        )),
      ]),
    ),
  );
}
