import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Админ панел — зөвхөн is_admin хэрэглэгч. Статистик + удирдлагын хэсгүүд.
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  int? _users, _posts, _pending, _banned;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<int?> _count(String table, {String? col, dynamic val}) async {
    try {
      final base = SupabaseService.client.from(table);
      if (col != null) {
        return await base.select('id').eq(col, val).count(CountOption.exact)
            .then((r) => r.count);
      }
      return await base.count(CountOption.exact);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadStats() async {
    final r = await Future.wait([
      _count('profiles'),
      _count('posts'),
      _count('reports', col: 'status', val: 'pending'),
      _count('profiles', col: 'is_banned', val: true),
    ]);
    if (mounted) {
      setState(() {
        _users = r[0]; _posts = r[1]; _pending = r[2]; _banned = r[3];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          // Deep link-ээр орж ирсэн үед pop хийх юмгүй — settings рүү
          onPressed: () {
            if (context.canPop()) { context.pop(); } else { context.go('/settings'); }
          },
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Админ панел', style: AppTextStyles.h2),
        actions: [
          if (isAdmin)
            IconButton(onPressed: () { setState(() => _loading = true); _loadStats(); },
              icon: const Icon(Icons.refresh, color: AppColors.textPrimary)),
        ],
      ),
      body: !isAdmin
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 56, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text('Хандах эрхгүй', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              Text('Энэ хэсэг зөвхөн админд зориулагдсан.',
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
            ]))
          : ListView(padding: const EdgeInsets.all(16), children: [
              // ── Статистик ──
              Row(children: [
                _stat('Хэрэглэгч', _users, Icons.people_outline, AppColors.accentStart),
                const SizedBox(width: 12),
                _stat('Пост', _posts, Icons.grid_on, const Color(0xFF7B2FF7)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _stat('Хүлээгдэж буй\nмэдээлэл', _pending, Icons.flag_outlined, AppColors.error),
                const SizedBox(width: 12),
                _stat('Хориглосон', _banned, Icons.block, const Color(0xFFFF7B5C)),
              ]),
              const SizedBox(height: 24),

              Text('УДИРДЛАГА', style: AppTextStyles.labelSm.copyWith(
                  color: AppColors.textSecondary, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              _tile(Icons.flag_outlined, 'Мэдээллүүд',
                  'Хэрэглэгчдийн мэдээлсэн контент',
                  () => context.push('/admin/reports')),
              _tile(Icons.people_outline, 'Хэрэглэгчид',
                  'Хайх, хориглох / сэргээх',
                  () => context.push('/admin/users')),
            ]),
    );
  }

  Widget _stat(String label, int? value, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 10),
        // Утга ирэхэд зөөлөн солигдоно
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          child: Text(_loading ? '…' : (value?.toString() ?? '—'),
              key: ValueKey(_loading ? '…' : '$value'),
              style: AppTextStyles.displaySm.copyWith(color: AppColors.textPrimary))),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
      ]),
    ),
  );

  // GestureDetector → InkWell: web дээр hover cursor + ripple feedback өгнө
  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: AppColors.accentStart, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
              Text(sub, style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      ),
    ),
  );
}
