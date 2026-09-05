import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../../live/providers/live_provider.dart';
import '../providers/stories_provider.dart';
import '../screens/story_viewer_screen.dart';

// ─── Рингийн градиентууд ───
// Үзсэн story — бүдэг саарал (идэвхгүй төлөв тод ялгарна)
const _seenRing = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF3A3A44), Color(0xFF26262E)],
);
// Live — lime (зөвхөн live/success-д)
const _liveRing = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [AppColors.lime, AppColors.neonCyan],
);

/// Story rail — IG-2025 темплэйт эрэмбэ:
/// ЭХЭНД "Таны story" (миний аватар + градиент "+" badge), дараа нь live-ууд,
/// төгсгөлд бусдын story ринг (үзээгүй = storyRingGradient, үзсэн = бүдэг).
class LiveStoryBar extends ConsumerWidget {
  final List<StoryRing> rings;
  const LiveStoryBar({super.key, required this.rings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lives = ref.watch(activeLivesProvider).value ?? [];
    // Миний профайл — "Таны story" tile-д өөрийн аватар харуулна
    final myProfile = ref.watch(currentProfileProvider).valueOrNull;

    // Эрэмбэ: [Таны story] [live...] [бусдын story ринг...]
    final itemCount = 1 + lives.length + rings.length;

    return SizedBox(
      height: 102,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        itemCount: itemCount,
        itemBuilder: (ctx, i) {
          // 1) Таны story — ЭХНИЙ tile (миний аватар + "+" badge)
          if (i == 0) {
            return _MyStoryItem(
              avatarUrl: myProfile?.avatarUrl,
              initial: myProfile?.initial ?? '?',
              onTap: () => context.push('/story/create'),
            );
          }
          // 2) Live items
          if (i - 1 < lives.length) {
            final l = lives[i - 1];
            return _RingItem(
              avatarUrl: l.avatarUrl,
              label: l.displayName.replaceAll('@', ''),
              ring: _liveRing,
              glow: AppColors.lime,
              badge: 'LIVE',
              onTap: () => context.push('/live/view/${l.id}'),
            );
          }
          // 3) Story rings
          final idx = i - 1 - lives.length;
          final ring = rings[idx];
          return _RingItem(
            avatarUrl: ring.author.avatarUrl,
            label: ring.author.username?.replaceAll('@', '') ?? '',
            ring: ring.hasUnseenStories
                ? AppColors.storyRingGradient
                : _seenRing,
            glow: ring.hasUnseenStories ? AppColors.magenta : null,
            onTap: () async {
              // Viewer хаагдмагц үзсэн/үзээгүй рингийн төлөвийг сэргээнэ
              // (StoryService.markViewed story_views руу бичсэн ч provider
              //  дахин ачаалахгүй бол gradient ринг худал асаалттай үлддэг).
              await Navigator.of(context).push(PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, __, ___) =>
                    StoryViewerScreen(rings: rings, initialRingIndex: idx),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c)));
              // Widget viewer нээлттэй байхад dispose болсон бол ref ашиглахгүй
              if (context.mounted) ref.invalidate(storiesProvider);
            },
          );
        },
      ),
    );
  }
}

class _RingItem extends StatelessWidget {
  final String? avatarUrl;
  final String label;
  final Gradient ring;
  final Color? glow; // ринг тойрсон зөөлөн неон гэрэл
  final String? badge;
  final VoidCallback onTap;
  const _RingItem({
    required this.avatarUrl,
    required this.label,
    required this.ring,
    required this.onTap,
    this.glow,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
            Container(
              width: 64, height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ring,
                boxShadow: glow == null ? null : [
                  BoxShadow(
                    color: glow!.withValues(alpha: 0.28),
                    blurRadius: 12, spreadRadius: -1),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.bgBase),
                child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 52),
              ),
            ),
            if (badge != null)
              Positioned(bottom: -4, child: _LivePulseBadge(text: badge!)),
          ]),
          const SizedBox(height: 6),
          SizedBox(width: 68, child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textSecondary, letterSpacing: 0.2))),
        ]),
      ),
    );
  }
}

/// LIVE badge — lime дэвсгэр, 1.6с зөөлөн glow pulse
class _LivePulseBadge extends StatefulWidget {
  final String text;
  const _LivePulseBadge({required this.text});
  @override
  State<_LivePulseBadge> createState() => _LivePulseBadgeState();
}

class _LivePulseBadgeState extends State<_LivePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.bgBase, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.lime.withValues(alpha: 0.2 + 0.3 * _c.value),
            blurRadius: 8 + 4 * _c.value),
        ],
      ),
      child: child,
    ),
    child: Text(widget.text, style: const TextStyle(
      color: AppColors.bgBase, fontSize: 8,
      fontWeight: FontWeight.w900, letterSpacing: 0.4)),
  );
}

/// "Таны story" — миний аватар 64 + баруун доод градиент "+" badge
/// (IG темплэйтийн адил өөрийн нүүрээр эхэлдэг rail)
class _MyStoryItem extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final VoidCallback onTap;
  const _MyStoryItem({
    required this.avatarUrl,
    required this.initial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            // Аватар — нарийн hairline хүрээтэй (ринггүй, "өөрийн" төлөв)
            Container(
              width: 64, height: 64,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline2, width: 1.5)),
              child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 58),
            ),
            // Градиент "+" badge — баруун доод булан
            Positioned(right: -2, bottom: -2, child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle, gradient: AppColors.accentGradient,
                border: Border.all(color: AppColors.bgBase, width: 2),
                boxShadow: AppColors.glowShadow(AppColors.accentStart,
                  alpha: 0.4, blur: 10, offset: const Offset(0, 2))),
              child: const Icon(Icons.add, color: Colors.white, size: 13))),
          ]),
          const SizedBox(height: 6),
          SizedBox(width: 68, child: Text('Таны story',
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textSecondary, letterSpacing: 0.2))),
        ]),
      ),
    );
  }
}

// Дарахад жижигрэх + hover курсор — веб мэдрэмж
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child),
      ),
    );
  }
}
