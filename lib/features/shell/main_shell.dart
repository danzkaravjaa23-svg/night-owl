import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../../core/providers/user_settings_provider.dart';
import '../../core/widgets/night_owl_brand.dart';
import '../../core/widgets/sculpted_icon.dart';
import '../../core/widgets/app_motion.dart';

/// Bottom nav shell — center-FAB template (Instagram/TikTok маягийн док)
class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    // Online статус — минут тутам last_seen_at шинэчилнэ (heartbeat)
    _beat();
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _beat());
  }

  Future<void> _beat() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      final notifier = ref.read(userSettingsProvider.notifier);
      await notifier.ready;
      if (!mounted || !ref.read(userSettingsProvider).activity) return;
      if (SupabaseService.currentUser?.id != me) return;
      await SupabaseService.client.from('profiles').update({
        'last_seen_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', me);
      // A privacy toggle may have completed while this request was in flight.
      if (mounted &&
          SupabaseService.currentUser?.id == me &&
          !ref.read(userSettingsProvider).activity) {
        await SupabaseService.client
            .from('profiles')
            .update({'last_seen_at': null}).eq('id', me);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final shell = Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBody: false,
      body: wide
          ? Row(children: [
              const SizedBox(width: 200, child: _DesktopNavigation()),
              Expanded(
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: widget.child))),
            ])
          : widget.child,
      bottomNavigationBar: wide ? null : _BottomNav(),
    );
    if (kIsWeb) return shell; // web-д browser back history-гоор явна
    final atFeed = _atFeed;
    return BackButtonListener(
      onBackButtonPressed: _onBack,
      // Feed биш tab дээр predictive back-ийг систем биш Flutter хүлээж авна
      child: PopScope(
        canPop: atFeed,
        child: NotificationListener<NavigationNotification>(
          // Shell navigator-ийн "pop боломжгүй" мэдэгдэл PopScope-ийг дарахгүй байх
          onNotification: (n) {
            if (atFeed || n.canHandlePop) return false;
            const NavigationNotification(canHandlePop: true).dispatch(context);
            return true;
          },
          child: shell,
        ),
      ),
    );
  }

  bool get _atFeed => GoRouterState.of(context).uri.path == AppRoutes.feed;

  // Feed биш tab дээр pop хийх зүйлгүй бол back → Feed (аппаас гарахгүй)
  Future<bool> _onBack() async {
    if (_atFeed || GoRouter.of(context).canPop()) return false;
    context.go(AppRoutes.feed);
    return true;
  }
}

class _BottomNav extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = _indexFromLocation(GoRouterState.of(context).uri.path);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border(
            top: BorderSide(color: AppColors.hairline.withValues(alpha: .08))),
      ),
      child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(children: [
              _NavItem(
                  icon: Icons.location_on_outlined,
                  activeIcon: Icons.location_on_outlined,
                  label: 'Газрууд',
                  isActive: index == 0,
                  onTap: () => context.go(AppRoutes.explore)),
              _NavItem(
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_outline_rounded,
                  label: 'Нийтлэл',
                  isActive: index == 1,
                  onTap: () => context.go(AppRoutes.feed)),
              Expanded(
                  child: Center(
                      child:
                          _CreateFab(onTap: () => _showCreateSheet(context)))),
              _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_outline_rounded,
                  label: 'Мессеж',
                  isActive: index == 3,
                  onTap: () => context.go(AppRoutes.dmList)),
              _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_outline_rounded,
                  label: 'Профайл',
                  isActive: index == 4,
                  onTap: () => context.go(AppRoutes.profile)),
            ]),
          )),
    );
  }

  void _showCreateSheet(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true, // контентдээ багтаж overflow гарахгүй
      showDragHandle: false,
      sheetAnimationStyle: AppMotion.reduced(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.enter, reverseDuration: AppMotion.exit),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Шинээр үүсгэх', style: AppTextStyles.h2),
            const SizedBox(height: 20),

            // Нийтлэл
            _CreateOption(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Нийтлэл',
              subtitle: 'Зураг эсвэл видео хуваалцах',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createPost);
              },
            ),
            const SizedBox(height: 12),

            _CreateOption(
              icon: Icons.add_circle_outline_rounded,
              label: 'Story',
              subtitle: 'Өнөө оройн мөчөө хуваалцах',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createStory);
              },
            ),
            const SizedBox(height: 12),

            // Богино видео (зөвхөн venue эзэд)
            _CreateOption(
              icon: Icons.explore_outlined,
              label: 'Богино видео',
              subtitle: 'Зөвхөн газрын эзэд нийтэлнэ',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createReel);
              },
            ),
            const SizedBox(height: 12),

            // Эвент
            _CreateOption(
              icon: Icons.event_rounded,
              label: 'Эвент',
              subtitle: 'Үйл явдал зарлах (бизнес)',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createEvent);
              },
            ),
          ]),
        )),
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith('/feed')) return 1;
    if (location.startsWith('/explore')) return 0;
    if (location.startsWith('/map')) return 0;
    if (location.startsWith('/reels')) return 1;
    if (location.startsWith('/dm')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 1;
  }
}

/// Persistent labels make destinations discoverable without guessing icons.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
            selected: isActive,
            child: PressFeedback(
                pressedScale: .95,
                child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    minimumSize: const Size(48, 64),
                    foregroundColor: isActive
                        ? AppColors.accentStart
                        : AppColors.textTertiary,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                        duration:
                            AppMotion.duration(context, AppMotion.release),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? AppColors.accentStart.withValues(alpha: .12)
                                : Colors.transparent),
                        child: SculptedIcon(isActive ? activeIcon : icon,
                            size: 24, active: isActive)),
                    const SizedBox(height: 3),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w500))),
                  ]),
                ))),
      );
}

class _CreateFab extends StatefulWidget {
  final VoidCallback onTap;
  const _CreateFab({required this.onTap});

  @override
  State<_CreateFab> createState() => _CreateFabState();
}

class _CreateFabState extends State<_CreateFab> {
  @override
  Widget build(BuildContext context) {
    return Semantics(
        button: true,
        label: 'Шинээр үүсгэх',
        child: Tooltip(
            message: 'Шинээр үүсгэх',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onTap,
                child: PressFeedback(
                  pressedScale: .94,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF9879EC),
                            Color(0xFF7654D6),
                            Color(0xFF503294)
                          ]),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFBCA6F8).withValues(alpha: .5)),
                      boxShadow: [
                        const BoxShadow(
                            color: Color(0xFF493079),
                            offset: Offset(0, 3),
                            blurRadius: 0),
                        BoxShadow(
                            color: Colors.black.withValues(
                                alpha: AppColors.isDarkMode ? .32 : .14),
                            offset: const Offset(0, 5),
                            blurRadius: 10),
                      ],
                    ),
                    child: const Center(
                        child: SculptedIcon(Icons.auto_fix_high_rounded,
                            color: Colors.white, size: 24, onDark: true)),
                  ),
                ),
              ),
            )));
  }
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: PressFeedback(
              pressedScale: .985,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(
                        child: SculptedIcon(icon,
                            color: Colors.white, size: 26, onDark: true)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label, style: AppTextStyles.labelLg),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            style: AppTextStyles.bodyXs
                                .copyWith(color: AppColors.textSecondary)),
                      ])),
                  Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ]),
              )),
        ),
      );
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation();
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    const destinations = [
      (AppRoutes.explore, Icons.location_on_outlined, 'Газрууд'),
      (AppRoutes.feed, Icons.people_outline_rounded, 'Нийтлэл'),
      (AppRoutes.reels, Icons.smart_display_outlined, 'Богино видео'),
      (AppRoutes.dmList, Icons.chat_bubble_outline_rounded, 'Мессеж'),
      (AppRoutes.profile, Icons.person_outline_rounded, 'Профайл'),
      (AppRoutes.saved, Icons.bookmark_border_rounded, 'Хадгалсан'),
    ];
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const NightOwlBrand(size: 26),
                  const SizedBox(height: 32),
                  for (final destination in destinations)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                            selected: location == destination.$1,
                            selectedColor: AppColors.silver,
                            selectedTileColor:
                                AppColors.silver.withValues(alpha: 0.12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            leading: SculptedIcon(destination.$2,
                                size: 22, active: location == destination.$1),
                            title: Text(destination.$3,
                                style: const TextStyle(fontSize: 13)),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            onTap: () => context.go(destination.$1))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: () => _BottomNav()._showCreateSheet(context),
                      icon: const SculptedIcon(Icons.add_rounded,
                          size: 18, color: Colors.white, onDark: true),
                      label: const Text('Нийтлэх')),
                  const Spacer(),
                  Text('УЛААНБААТАР\nAFTER HOURS',
                      style: AppTextStyles.labelSm),
                  const SizedBox(height: 24),
                ])));
  }
}
