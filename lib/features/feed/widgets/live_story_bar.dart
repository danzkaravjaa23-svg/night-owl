import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../models/story.dart';
import '../../live/providers/live_provider.dart';
import '../screens/story_viewer_screen.dart';

/// Live + Story нэг хэвтээ мөрөнд: эхэлж live-ууд, дараа нь "+Таны story",
/// дараа нь бусдын story ринг.
class LiveStoryBar extends ConsumerWidget {
  final List<StoryRing> rings;
  const LiveStoryBar({super.key, required this.rings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lives = ref.watch(activeLivesProvider).value ?? [];

    // Эрэмбэ: [live...] [add-story] [story rings...]
    final itemCount = lives.length + 1 + rings.length;

    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: itemCount,
        itemBuilder: (ctx, i) {
          // 1) Live items
          if (i < lives.length) {
            final l = lives[i];
            return _RingItem(
              avatarUrl: l.avatarUrl,
              label: l.displayName.replaceAll('@', ''),
              ringColors: const [Color(0xFFFF3B30), Color(0xFFFF9500)],
              badge: 'LIVE',
              onTap: () => context.push('/live/view/${l.id}'),
            );
          }
          // 2) Add your story
          if (i == lives.length) {
            return _AddStoryItem(onTap: () => context.push('/story/create'));
          }
          // 3) Story rings
          final idx = i - lives.length - 1;
          final ring = rings[idx];
          return _RingItem(
            avatarUrl: ring.author.avatarUrl,
            label: ring.author.username?.replaceAll('@', '') ?? '',
            ringColors: ring.hasUnseenStories
                ? const [Color(0xFFFF3B7B), Color(0xFFFF9500)]
                : const [Color(0xFF444444), Color(0xFF444444)],
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              opaque: false,
              pageBuilder: (_, __, ___) =>
                  StoryViewerScreen(rings: rings, initialRingIndex: idx),
              transitionsBuilder: (_, a, __, c) =>
                  FadeTransition(opacity: a, child: c))),
          );
        },
      ),
    );
  }
}

class _RingItem extends StatelessWidget {
  final String? avatarUrl;
  final String label;
  final List<Color> ringColors;
  final String? badge;
  final VoidCallback onTap;
  const _RingItem({
    required this.avatarUrl,
    required this.label,
    required this.ringColors,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return GestureDetector(
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
                gradient: LinearGradient(colors: ringColors,
                  begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.bgBase),
                child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 52),
              ),
            ),
            if (badge != null)
              Positioned(bottom: -4, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.bgBase, width: 1.5)),
                child: Text(badge!, style: const TextStyle(
                  color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)))),
          ]),
          const SizedBox(height: 6),
          SizedBox(width: 66, child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))),
        ]),
      ),
    );
  }
}

class _AddStoryItem extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStoryItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.bgSurface,
                border: Border.all(color: AppColors.hairline)),
              child: const Icon(Icons.add_a_photo_outlined,
                  color: AppColors.textSecondary, size: 24)),
            Positioned(right: 0, bottom: 0, child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle, gradient: AppColors.accentGradient,
                border: Border.all(color: AppColors.bgBase, width: 2)),
              child: const Icon(Icons.add, color: Colors.white, size: 12))),
          ]),
          const SizedBox(height: 6),
          SizedBox(width: 66, child: Text('Таны story',
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))),
        ]),
      ),
    );
  }
}
