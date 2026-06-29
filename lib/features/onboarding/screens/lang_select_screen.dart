import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';

class LangSelectScreen extends StatefulWidget {
  const LangSelectScreen({super.key});

  @override
  State<LangSelectScreen> createState() => _LangSelectScreenState();
}

class _LangSelectScreenState extends State<LangSelectScreen> {
  String _selected = 'en';

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', _selected);
    if (!mounted) return;
    context.go('${AppRoutes.onboarding}?slide=1');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              const Text('🦉', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 32),
              Text(
                'Choose Language',
                style: AppTextStyles.displaySm,
                textAlign: TextAlign.center,
              ),
              Text(
                'Хэлээ сонгоно уу',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              _LangTile(
                flag: '🇺🇸', lang: 'English', native: 'English',
                isSelected: _selected == 'en',
                onTap: () => setState(() => _selected = 'en'),
              ),
              const SizedBox(height: 12),
              _LangTile(
                flag: '🇲🇳', lang: 'Mongolian', native: 'Монгол',
                isSelected: _selected == 'mn',
                onTap: () => setState(() => _selected = 'mn'),
              ),
              const Spacer(),
              GradientButton(
                label: _selected == 'mn' ? 'Үргэлжлүүлэх' : 'Continue',
                onPressed: _continue,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final String flag, lang, native;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangTile({
    required this.flag,
    required this.lang,
    required this.native,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.bgSurface : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accentStart : AppColors.hairline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    native,
                    style: AppTextStyles.h3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    lang,
                    style: AppTextStyles.bodyXs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
