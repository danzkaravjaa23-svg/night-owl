import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../utils/app_links.dart';

/// Түншлэлийн хөтөлбөр — газар/найз урьж, урамшуулал авах.
/// unlockMode=true үед "нээх" урсгалыг харуулна (SharedPreferences-т төлөв хадгална).
class AffiliateScreen extends StatefulWidget {
  final bool unlockMode;
  const AffiliateScreen({super.key, this.unlockMode = false});

  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen> {
  static const _prefsKey = 'affiliate_unlocked';
  bool _unlocked = false;
  bool _loadingState = true;

  @override
  void initState() {
    super.initState();
    _loadUnlocked();
  }

  Future<void> _loadUnlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _unlocked = prefs.getBool(_prefsKey) ?? false;
          _loadingState = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingState = false);
    }
  }

  Future<void> _unlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {/* локал хадгалалт бүтэлгүйтвэл ч UI-г нээнэ */}
    if (mounted) {
      setState(() => _unlocked = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Түншлэлийн хандалт нээгдлээ ✓'),
        behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _shareLink() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final ref = uid.length >= 8 ? uid.substring(0, 8) : uid;
    final link = inviteLink(ref);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Урилгын холбоос хуулагдлаа 🔗 $link'),
        duration: const Duration(seconds: 3)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // unlockMode + хараахан нээгдээгүй бол "нээх" товч, эс бол "холбоос хуваалцах"
    final showUnlockCta = widget.unlockMode && !_unlocked;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Түншлэлийн хөтөлбөр', style: AppTextStyles.h2),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🦉', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text('Night Owl-той хамт олоорой', style: AppTextStyles.displaySm,
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('Найз, газраа урьж, гишүүнчлэл бүрээс урамшуулал ав.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center),
          if (_unlocked && widget.unlockMode) ...[
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle,
                color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Text('Идэвхтэй ✓', style: AppTextStyles.labelMd.copyWith(
                color: AppColors.success)),
            ]),
          ],
          const SizedBox(height: 40),
          if (_loadingState)
            const SizedBox(
              height: 22, width: 22,
              child: CircularProgressIndicator(
                color: AppColors.accentStart, strokeWidth: 2))
          else
            GradientButton(
              label: showUnlockCta
                ? 'Түншлэл нээх'
                : 'Холбоосоо хуваалцах',
              onPressed: () => showUnlockCta ? _unlock() : _shareLink(),
            ),
        ]),
      ),
    );
  }
}
