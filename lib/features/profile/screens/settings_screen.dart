import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../models/user_profile.dart';
import '../../../core/providers/user_settings_provider.dart';
import '../../../core/widgets/policy_links.dart';
import '../../auth/services/account_metadata_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final AccountMetadataService? metadataService;
  const SettingsScreen({super.key, this.metadataService});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  bool _savingConsent = false;
  bool _signingOut = false;

  Future<void> _setAnalyticsConsent(bool value) async {
    if (_savingConsent) return;
    final owner = ref.read(sessionUserIdProvider);
    if (owner == null) return;
    setState(() => _savingConsent = true);
    try {
      final applied = await (widget.metadataService ?? AccountMetadataService())
          .update({'discovery_analytics_consent': value}, ownerId: owner);
      if (!mounted || owner != ref.read(sessionUserIdProvider)) return;
      if (!applied) _toast('Хаяг өөрчлөгдсөн байна. Дахин нэвтэрч оролдоорой.');
    } catch (_) {
      if (mounted && owner == ref.read(sessionUserIdProvider)) {
        _toast('Зөвшөөрлийг хадгалж чадсангүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(AppRoutes.authLanding);
    } catch (_) {
      if (mounted) {
        _toast('Гарч чадсангүй. Холболтоо шалгаад дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  /// Профайл засах — тусгай editProfile route (/auth/setup биш: router
  /// бүртгэл дууссан хэрэглэгчийг feed руу буцаадаг). Буцаж ирэхэд шинэчилнэ.
  Future<void> _openEditProfile() async {
    await context.push(AppRoutes.editProfile);
    if (mounted) ref.invalidate(currentProfileProvider);
  }

  // Switch-үүдийг мөр дарахад ч, switch дарахад ч ижил замаар солино
  Future<void> _setNotifLikes(bool v) async {
    try {
      await ref.read(userSettingsProvider.notifier).setNotifications(v);
    } catch (_) {
      if (mounted) _toast('Тохиргоо хадгалж чадсангүй');
    }
  }

  Future<void> _setActivityStatus(bool value) async {
    try {
      await ref.read(userSettingsProvider.notifier).setActivity(value);
    } catch (_) {
      if (mounted) _toast('Тохиргоо хадгалж чадсангүй');
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    try {
      await ref.read(themeModeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        _toast('Өнгөний горим хадгалж чадсангүй. Дахин оролдоно уу.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final owner = ref.watch(sessionUserIdProvider);
    final authUser =
        owner == null ? null : ref.watch(authUserProvider).valueOrNull;
    final analytics =
        authUser?.userMetadata?['discovery_analytics_consent'] == true;
    final preferences = ref.watch(userSettingsProvider);
    final notifLikes = preferences.notifications;
    final activityStatus = preferences.activity;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              _Header(
                  onBack: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.profile)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    profileAsync.when(
                      data: (p) =>
                          _ProfileCard(profile: p, onTap: _openEditProfile),
                      loading: () => const _ProfileCardSkeleton(),
                      error: (_, __) =>
                          _ProfileCard(profile: null, onTap: _openEditProfile),
                    ),
                    const SizedBox(height: 24),
                    _GlassCard(children: [
                      _AppearanceChooser(
                          selected: themeMode, onChanged: _setThemeMode),
                    ]),
                    const SizedBox(height: 28),
                    const _SectionLabel('Таны бүртгэл'),
                    const SizedBox(height: 12),
                    _GlassCard(children: [
                      _SettingRow(
                          icon: Icons.person_outline,
                          label: 'Профайл засах',
                          sub: 'Нэр, зураг, танилцуулга',
                          onTap: _openEditProfile),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.lock_outline,
                          label: 'Нууц үг солих',
                          onTap: () => context.push(AppRoutes.changePassword)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.language_outlined,
                          label: 'Хэл',
                          trailingValue: 'Монгол',
                          onTap: () => context.push(AppRoutes.langSelect)),
                    ]),
                    const SizedBox(height: 28),
                    const _SectionLabel('Нууцлал ба мэдэгдэл'),
                    const SizedBox(height: 12),
                    _GlassCard(children: [
                      _SettingRow(
                          icon: Icons.lock_person_outlined,
                          label: 'Нууцлал, хүсэлтүүд',
                          sub: 'Хэн тантай холбогдохыг тохируулах',
                          onTap: () => context.push('/privacy'),
                          disabled: profileAsync.isLoading),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.notifications_none,
                          label: 'Апп доторх мэдэгдэл',
                          sub: 'Энэ төхөөрөмж дээр',
                          onTap: () => _setNotifLikes(!notifLikes),
                          trailing: _NeonSwitch(
                              value: notifLikes, onChanged: _setNotifLikes)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.radar_outlined,
                          label: 'Идэвхтэй төлөв',
                          sub: 'Энэ төхөөрөмжөөс идэвхтэй төлөв харуулах',
                          onTap: () => _setActivityStatus(!activityStatus),
                          trailing: _NeonSwitch(
                              value: activityStatus,
                              onChanged: _setActivityStatus)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.insights_outlined,
                          label: 'Хэрэглээний статистик',
                          sub: 'Сайжруулахад туслах зорилгоор нээсэн хуудас, '
                              'хадгалалт зэрэг үйлдлийг бүртгэхийг зөвшөөрнө. '
                              'Сонголттой, хүссэн үедээ унтрааж болно.',
                          disabled: owner == null || _savingConsent,
                          onTap: () => _setAnalyticsConsent(!analytics),
                          trailing: _NeonSwitch(
                              value: analytics,
                              onChanged: owner == null || _savingConsent
                                  ? null
                                  : _setAnalyticsConsent)),
                    ]),
                    const SizedBox(height: 28),
                    const _SectionLabel('Night Owl'),
                    const SizedBox(height: 12),
                    _GlassCard(children: [
                      if (profileAsync.asData?.value?.canModerate(owner) ==
                          true) ...[
                        _SettingRow(
                            icon: Icons.admin_panel_settings_outlined,
                            label: 'Админ панел',
                            sub: 'Гомдол, хэрэглэгч, контент ба үйлдлийн түүх',
                            onTap: () => context.push(AppRoutes.adminPanel)),
                        const _RowDivider(),
                      ],
                      _SettingRow(
                          icon: Icons.business_center_outlined,
                          label: 'Бизнес самбар',
                          sub: 'Газрынхаа мэдээллийг удирдах',
                          onTap: () => context.push(AppRoutes.business)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Найзаа урих',
                          onTap: () => context.push(AppRoutes.invite)),
                    ]),
                    const SizedBox(height: 28),
                    const _SectionLabel('Тусламж ба мэдээлэл'),
                    const SizedBox(height: 12),
                    _GlassCard(children: [
                      _SettingRow(
                          icon: Icons.help_outline,
                          label: 'Тусламж',
                          onTap: () =>
                              openAppPolicy(context, AppPolicy.support)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Нууцлалын бодлого',
                          onTap: () =>
                              openAppPolicy(context, AppPolicy.privacy)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.description_outlined,
                          label: 'Үйлчилгээний нөхцөл',
                          onTap: () => openAppPolicy(context, AppPolicy.terms)),
                      const _RowDivider(),
                      _SettingRow(
                          icon: Icons.article_outlined,
                          label: 'Лицензүүд',
                          onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'Night Owl UB',
                              applicationVersion: '1.0.0')),
                      const _RowDivider(),
                      const _SettingRow(
                          icon: Icons.account_tree_outlined,
                          label: 'Хувилбар · Үнэгүй',
                          trailingValue: '1.0.0',
                          mono: true),
                    ]),
                    const SizedBox(height: 28),
                    _NeutralButton(
                        label: _signingOut ? 'Гарч байна…' : 'Гарах',
                        icon: Icons.logout,
                        onTap: _signingOut ? null : _signOut),
                    const SizedBox(height: 12),
                    TextButton.icon(
                        onPressed: () => context.push(AppRoutes.deleteAccount),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14)),
                        icon:
                            const Icon(Icons.person_remove_outlined, size: 20),
                        label: const Text('Бүртгэл устгах',
                            textAlign: TextAlign.center)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AppearanceChooser extends StatelessWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;
  const _AppearanceChooser({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Харагдах байдал', style: AppTextStyles.h3),
        const SizedBox(height: 6),
        Text('Өөрт эвтэйхэн горимоо сонгоорой.',
            style: AppTextStyles.bodySm.copyWith(height: 1.45)),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          const options = [
            (ThemeMode.light, 'Өдөр'),
            (ThemeMode.dark, 'Шөнө'),
            (ThemeMode.system, 'Систем'),
          ];
          final labelWidth = (constraints.maxWidth - 16) / 3 - 20;
          final stacked = options.any((option) {
            final painter = TextPainter(
                text: TextSpan(text: option.$2, style: AppTextStyles.labelLg),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context),
                maxLines: 1)
              ..layout();
            final doesNotFit = painter.width > labelWidth;
            painter.dispose();
            return doesNotFit;
          });
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final option in options)
              SizedBox(
                  width: stacked
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 3,
                  child: Semantics(
                      button: true,
                      selected: selected == option.$1,
                      child: Material(
                          color: selected == option.$1
                              ? AppColors.silver.withValues(alpha: .08)
                              : AppColors.bgBase,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                  width: selected == option.$1 ? 1.5 : 1,
                                  color: selected == option.$1
                                      ? AppColors.silver
                                      : AppColors.hairline)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              onTap: () => onChanged(option.$1),
                              child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: stacked
                                      ? Row(children: [
                                          SizedBox(
                                              width: 64,
                                              child: _AppearancePreview(
                                                  mode: option.$1)),
                                          const SizedBox(width: 14),
                                          Expanded(
                                              child: Text(option.$2,
                                                  style:
                                                      AppTextStyles.labelLg)),
                                          if (selected == option.$1)
                                            Icon(Icons.check_circle_rounded,
                                                size: 20,
                                                color: AppColors.silver),
                                        ])
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                              _AppearancePreview(
                                                  mode: option.$1),
                                              const SizedBox(height: 10),
                                              Text(option.$2,
                                                  textAlign: TextAlign.center,
                                                  style: AppTextStyles.labelLg
                                                      .copyWith(
                                                          color: selected ==
                                                                  option.$1
                                                              ? AppColors.silver
                                                              : AppColors
                                                                  .textSecondary)),
                                            ])))))),
          ]);
        }),
        const SizedBox(height: 12),
        Text('Систем горим төхөөрөмжийн тохиргоог дагана.',
            style: AppTextStyles.bodySm.copyWith(height: 1.45)),
      ]));
}

/// Small previews make each appearance choice recognizable before selecting it.
class _AppearancePreview extends StatelessWidget {
  final ThemeMode mode;
  const _AppearancePreview({required this.mode});

  @override
  Widget build(BuildContext context) {
    final dark = mode == ThemeMode.dark;
    final surface = dark ? const Color(0xFF252C43) : const Color(0xFFE4E1EF);
    return ExcludeSemantics(
        child: Container(
            height: 48,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: dark ? AppColors.bgBaseDark : AppColors.bgElevatedLight,
                gradient: mode == ThemeMode.system
                    ? const LinearGradient(colors: [
                        AppColors.bgElevatedLight,
                        AppColors.bgElevatedLight,
                        AppColors.bgBaseDark,
                        AppColors.bgBaseDark,
                      ], stops: [
                        0,
                        .5,
                        .5,
                        1
                      ])
                    : null),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: AppColors.accentStart, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Expanded(child: Container(height: 3, color: surface)),
              ]),
              const SizedBox(height: 6),
              Expanded(
                  child: Container(
                      decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(4)),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Container(
                          width: 15,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppColors.accentStart,
                              borderRadius: BorderRadius.circular(3))))),
            ])));
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
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
              tooltip: 'Буцах',
              onPressed: onBack,
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: SculptedIcon(Icons.chevron_left,
                  color: AppColors.textPrimary, size: 22)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Тохиргоо', style: AppTextStyles.h1.copyWith(fontSize: 26)),
            ],
          )),
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
        : (p?.username ?? 'Профайл');
    final username = p?.username?.trim().replaceFirst(RegExp(r'^@+'), '');
    final sub = username != null && username.isNotEmpty
        ? '@$username'
        : 'Мэдээллээ шинэчлэх';
    final avatarUrl = p?.avatarUrl;

    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Keep the person's image inside the reference violet ring.
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.silver, AppColors.accentStart],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgBase,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: AppAvatar(imageUrl: avatarUrl, size: 55),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h2.copyWith(height: 1.25),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 'LIVE' pill байсан нь худал (жинхэнэ live төлөвтэй холбоогүй) —
              // "Профайл засах" гэдгийг илэрхийлсэн саармаг chevron-оор солив.
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
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
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 11,
                  width: 180,
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
          label,
          style: AppTextStyles.labelLg.copyWith(color: AppColors.textSecondary),
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
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: children),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            left: MediaQuery.sizeOf(context).width < 380 &&
                    MediaQuery.textScalerOf(context).scale(14) > 19
                ? 12
                : 56,
            right: 12),
        child: Divider(height: 1, thickness: 1, color: AppColors.hairline),
      );
}

// ─────────────────────────────────────────────────────────────
//  Setting row — violet icon tile + label + trailing
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
    final iconColor = disabled ? AppColors.textTertiary : AppColors.silver;
    final largeText = MediaQuery.sizeOf(context).width < 380 &&
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final row = Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        child: Row(
          children: [
            // At larger text sizes, give the description the icon's space.
            if (!largeText) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(child: Icon(icon, size: 21, color: iconColor)),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppTextStyles.h3),
                  if (sub != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      sub!,
                      style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],
                  if (trailingValue != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      trailingValue!,
                      style: mono
                          ? AppTextStyles.mono.copyWith(
                              color: AppColors.textTertiary, fontSize: 12)
                          : AppTextStyles.bodySm
                              .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null && !disabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
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
//  Violet switch
// ─────────────────────────────────────────────────────────────
class _NeonSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _NeonSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Дүрс нь 46×28 хэвээр, харин дарах талбайг 44px өндөр болгов
    return Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: MouseRegion(
          cursor:
              onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 46,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: value ? AppColors.accentStart : AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          value ? AppColors.accentStart : AppColors.hairline2,
                    ),
                  ),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? Colors.white : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}

// ─────────────────────────────────────────────────────────────
//  Neutral (secondary) button — буцаах боломжтой үйлдэлд
// ─────────────────────────────────────────────────────────────
class _NeutralButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _NeutralButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          backgroundColor: AppColors.bgSurface.withValues(alpha: .7),
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.hairline2),
          textStyle: AppTextStyles.btn,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center));
}
