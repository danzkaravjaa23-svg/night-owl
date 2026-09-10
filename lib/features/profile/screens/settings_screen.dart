import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../models/user_profile.dart';
import '../widgets/invite_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Тохиргоо — SharedPreferences-т хадгалагдана (ThemeModeNotifier шиг)
  static const _kNotif = 'settings_notif';
  static const _kActivity = 'settings_activity_status';
  bool _notifLikes = true;
  bool _activityStatus = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notifLikes = prefs.getBool(_kNotif) ?? true;
        _activityStatus = prefs.getBool(_kActivity) ?? true;
      });
    } catch (_) {/* prefs уншиж чадвал default утга ашиглана */}
  }

  Future<void> _setPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {/* локал хадгалалт бүтэлгүйтэвч UI төлөв хадгалагдана */}
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  // Switch-үүдийг мөр дарахад ч, switch дарахад ч ижил замаар солино
  void _setNotifLikes(bool v) {
    setState(() => _notifLikes = v);
    _setPref(_kNotif, v);
  }

  void _setActivityStatus(bool v) {
    setState(() => _activityStatus = v);
    _setPref(_kActivity, v);
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Данс устгах уу?', style: AppTextStyles.h3),
        content: Text(
          'Таны бүх пост, сэтгэгдэл, дагалт, мессеж бүрмөсөн устана. '
          'Энэ үйлдлийг буцаах боломжгүй.',
          style: AppTextStyles.bodySm.copyWith(
            color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text('Бүрмөсөн устгах', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;

    // 1) Edge function-аар auth хэрэглэгч + бүх датаг бүрмөсөн устгахыг оролдоно
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(AppRoutes.authLanding);
      return;
    } on FunctionException catch (e) {
      // Зөвхөн function байхгүй (404) үед л profiles-only fallback руу орно.
      // Бусад алдааг (RLS/сүлжээ) хэрэглэгчид харуулна — чимээгүй нуухгүй.
      if (e.status != 404) {
        if (mounted) _toast('Данс устгаж чадсангүй. Дахин оролдоно уу');
        return;
      }
    } catch (_) {
      if (mounted) _toast('Данс устгаж чадсангүй. Дахин оролдоно уу');
      return;
    }

    // 2) Fallback — function deploy хийгдээгүй тул profiles-ыг устгана (контент cascade).
    //    Гэхдээ auth хэрэглэгч устахгүй тул нэвтрэлт хэвээр үлдэхийг мэдэгдэнэ.
    try {
      await Supabase.instance.client.from('profiles').delete().eq('id', me);
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        _toast('Профайл устлаа. Нэвтрэх эрх серверт хэвээр — админд хандана уу');
        context.go(AppRoutes.authLanding);
      }
    } catch (_) {
      if (mounted) _toast('Данс устгаж чадсангүй. Дахин оролдоно уу');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ─── Aurora glow backdrop — magenta зүүн дээд, cyan баруун доод ───
          Positioned(
            top: -160, left: -120,
            child: Container(
              width: 360, height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.magenta.withValues(alpha: 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -140, right: -100,
            child: Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.neonCyan.withValues(alpha: 0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: () => context.pop()),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                    children: [
                      // ─── Profile glance card ───
                      profileAsync.when(
                        data: (p) => _ProfileCard(
                          profile: p,
                          onTap: () => context.push(AppRoutes.setup),
                        ),
                        loading: () => const _ProfileCardSkeleton(),
                        error: (_, __) => _ProfileCard(
                          profile: null,
                          onTap: () => context.push(AppRoutes.setup),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ─── БҮРТГЭЛ ───
                      const _SectionLabel('Бүртгэл'),
                      const SizedBox(height: 10),
                      _GlassCard(children: [
                        _SettingRow(
                          icon: Icons.person_outline,
                          label: 'Профайл засах',
                          onTap: () => context.push(AppRoutes.setup),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.lock_outline,
                          label: 'Нууц үг солих',
                          onTap: () => context.push(AppRoutes.changePassword),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.language_outlined,
                          label: 'Хэл',
                          trailingValue: 'Монгол',
                          onTap: () => context.push(AppRoutes.langSelect),
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // ─── ТОХИРГОО ───
                      const _SectionLabel('Тохиргоо'),
                      const SizedBox(height: 10),
                      // 'Харанхуй горим' сонголтыг түр хассан: апп даяар
                      // харанхуй өнгөний токенууд шууд бичигдсэн тул гэрэл
                      // горим эвдэрсэн харагдана. dyn* өнгөний шилжилт
                      // (migration) дуустал энэ мөрийг буцааж нэмэхгүй.
                      _GlassCard(children: [
                        _SettingRow(
                          icon: Icons.notifications_none,
                          label: 'Мэдэгдэл',
                          onTap: () => _setNotifLikes(!_notifLikes),
                          trailing: _NeonSwitch(
                            value: _notifLikes,
                            onChanged: _setNotifLikes,
                          ),
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // ─── НУУЦЛАЛ ───
                      const _SectionLabel('Нууцлал'),
                      const SizedBox(height: 10),
                      _GlassCard(children: [
                        // 'Хувийн данс' — profiles.is_private багана серверт байхгүй тул
                        // одоохондоо идэвхгүй ("тун удахгүй") болгосон.
                        const _SettingRow(
                          icon: Icons.lock_person_outlined,
                          label: 'Хувийн данс',
                          trailingValue: 'Тун удахгүй',
                          disabled: true,
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.radar_outlined,
                          label: 'Идэвхтэй төлөв',
                          sub: 'Найзууд таныг шөнө олох боломжтой',
                          onTap: () => _setActivityStatus(!_activityStatus),
                          trailing: _NeonSwitch(
                            value: _activityStatus,
                            onChanged: _setActivityStatus,
                          ),
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // ─── ТӨЛБӨР ───
                      const _SectionLabel('Төлбөр'),
                      const SizedBox(height: 10),
                      _GlassCard(children: [
                        // QPay түүх — payments хүснэгт серверт байхгүй тул идэвхгүй
                        const _SettingRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'QPay түүх',
                          trailingValue: 'Тун удахгүй',
                          disabled: true,
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.business_center_outlined,
                          label: 'Бизнес самбар',
                          onTap: () => context.push(AppRoutes.business),
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // ─── ТУХАЙ ───
                      const _SectionLabel('Тухай'),
                      const SizedBox(height: 10),
                      _GlassCard(children: [
                        _SettingRow(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Найзаа урих',
                          onTap: () => showInviteSheet(context),
                        ),
                        const _RowDivider(),
                        // Түншлэлийн хөтөлбөр — өмнө нь зөвхөн URL бичиж л хүрдэг байсан
                        _SettingRow(
                          icon: Icons.handshake_outlined,
                          label: 'Түншлэлийн хөтөлбөр',
                          onTap: () => context.push(AppRoutes.affiliate),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.help_outline,
                          label: 'Тусламж',
                          onTap: () => _toast('Тусламж: support@nightowl.mn'),
                        ),
                        const _RowDivider(),
                        const _SettingRow(
                          icon: Icons.account_tree_outlined,
                          label: 'Хувилбар',
                          trailingValue: '1.0.0',
                          mono: true,
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // ─── Actions ───
                      // 'Гарах' нь буцаах боломжтой үйлдэл тул саармаг товч
                      _NeutralButton(
                        label: 'Гарах',
                        icon: Icons.logout,
                        onTap: () async {
                          await Supabase.instance.client.auth.signOut();
                          if (context.mounted) {
                            context.go(AppRoutes.authLanding);
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      // 'Бүртгэл устгах' нь эргэшгүй тул жинхэнэ destructive товч
                      _DangerButton(
                        label: 'Бүртгэл устгах',
                        icon: Icons.delete_forever_outlined,
                        onTap: _deleteAccount,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: const Icon(Icons.chevron_left,
                    color: AppColors.textPrimary, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NIGHT OWL', style: AppTextStyles.labelSm),
              const SizedBox(height: 2),
              Text('Тохиргоо', style: AppTextStyles.h1),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Profile glance card
// ─────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onTap;
  const _ProfileCard({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = (p?.name?.trim().isNotEmpty ?? false)
        ? p!.name!.trim()
        : (p?.username ?? 'Night Owl');
    final username = p?.username;
    final bio = (p?.bio?.trim().isNotEmpty ?? false) ? p!.bio!.trim() : null;
    final sub = [
      if (username != null && username.isNotEmpty) '@$username',
      if (bio != null) bio,
    ].join(' · ');
    final avatarUrl = p?.avatarUrl;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.hairline2),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonCyan.withValues(alpha: 0.06),
              blurRadius: 28,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          children: [
            // Neon ring avatar
            Container(
              width: 64, height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.lime, AppColors.neonCyan],
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgBase,
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _avatarFallback(p?.initial ?? '?'),
                        )
                      : _avatarFallback(p?.initial ?? '?'),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h2,
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 'LIVE' pill байсан нь худал (жинхэнэ live төлөвтэй холбоогүй) —
            // "Профайл засах" гэдгийг илэрхийлсэн саармаг chevron-оор солив.
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
      ),
    );
  }

  Widget _avatarFallback(String initial) => Container(
        decoration: const BoxDecoration(gradient: AppColors.accentGradient),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: AppTextStyles.h2.copyWith(color: Colors.white),
        ),
      );
}

class _ProfileCardSkeleton extends StatelessWidget {
  const _ProfileCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgSurface,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14, width: 120,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 11, width: 180,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Section label (eyebrow)
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.labelSm.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Glass card container
// ─────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final List<Widget> children;
  const _GlassCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(children: children),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 56, right: 12),
        child: Divider(height: 1, thickness: 1, color: AppColors.hairline),
      );
}

// ─────────────────────────────────────────────────────────────
//  Setting row — cyan glass icon tile + label + trailing
// ─────────────────────────────────────────────────────────────
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final String? trailingValue;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool mono;
  final bool disabled; // идэвхгүй мөр (сааралдуулж, дарагдахгүй)
  const _SettingRow({
    required this.icon,
    required this.label,
    this.sub,
    this.trailingValue,
    this.trailing,
    this.onTap,
    this.mono = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        disabled ? AppColors.textTertiary : AppColors.neonCyan;
    final row = Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Row(
        children: [
          // Cyan glass icon tile
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: iconColor.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppTextStyles.h3),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: AppTextStyles.bodyXs
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (trailingValue != null) ...[
            const SizedBox(width: 8),
            Text(
              trailingValue!,
              style: mono
                  ? AppTextStyles.mono
                      .copyWith(color: AppColors.textTertiary, fontSize: 12)
                  : AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (onTap != null && !disabled) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ],
      ),
    ),
    );

    if (onTap == null || disabled) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: row,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Neon cyan switch
// ─────────────────────────────────────────────────────────────
class _NeonSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NeonSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Дүрс нь 46×28 хэвээр, харин дарах талбайг 44px өндөр болгов
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 46, height: 28,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value
              ? AppColors.neonCyan.withValues(alpha: 0.22)
              : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value
                ? AppColors.neonCyan.withValues(alpha: 0.55)
                : AppColors.hairline2,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.30),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? AppColors.neonCyan : AppColors.textTertiary,
          ),
        ),
      ),
        ),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Neutral (secondary) button — буцаах боломжтой үйлдэлд
// ─────────────────────────────────────────────────────────────
class _NeutralButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NeutralButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bgSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.btn.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Danger button — эргэшгүй (destructive) үйлдэлд
// ─────────────────────────────────────────────────────────────
class _DangerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DangerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.btn.copyWith(color: AppColors.error),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
