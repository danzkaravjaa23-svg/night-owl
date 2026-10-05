import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/stories_provider.dart';
import '../screens/story_viewer_screen.dart';

/// The first tile always belongs to the signed-in user. The remaining tiles
/// are actual story authors; unavailable live broadcasts are not advertised.
class LiveStoryBar extends ConsumerWidget {
  final List<StoryRing> rings;
  const LiveStoryBar({super.key, required this.rings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProfile = ref.watch(currentProfileProvider).valueOrNull;
    final myId = ref.watch(sessionUserIdProvider);
    final ownIndex = rings.indexWhere((ring) => ring.userId == myId);
    final others = rings.where((ring) => ring.userId != myId).toList();

    Future<void> openStory(int index) async {
      await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) =>
            StoryViewerScreen(rings: rings, initialRingIndex: index),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ));
      if (context.mounted) ref.invalidate(storiesProvider);
    }

    final labelPainter = TextPainter(
      text: TextSpan(
          text: 'Таны story',
          style: AppTextStyles.bodyXs.copyWith(fontSize: 11, height: 1.2)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 68);
    final railHeight =
        89.0 + (labelPainter.height > 21 ? labelPainter.height : 21.0);
    labelPainter.dispose();
    return SizedBox(
      height: railHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        itemCount: others.length + 1,
        itemBuilder: (_, index) {
          if (index == 0) {
            return _MyStoryItem(
              avatarUrl: myProfile?.avatarUrl,
              hasStory: ownIndex >= 0,
              onTap: () {
                if (ownIndex >= 0) {
                  openStory(ownIndex);
                } else {
                  context.push('/story/create');
                }
              },
              onAdd: () => context.push('/story/create'),
            );
          }
          final ring = others[index - 1];
          return _RingItem(
            avatarUrl: ring.author.avatarUrl,
            label: ring.author.username?.replaceAll('@', '') ?? 'Хэрэглэгч',
            unseen: ring.hasUnseenStories,
            onTap: () => openStory(rings.indexOf(ring)),
          );
        },
      ),
    );
  }
}

class _RingItem extends StatelessWidget {
  final String? avatarUrl;
  final String label;
  final bool unseen;
  final VoidCallback onTap;
  const _RingItem(
      {required this.avatarUrl,
      required this.label,
      required this.unseen,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: unseen ? AppColors.accentStart : AppColors.hairline2,
                    width: 1.8),
              ),
              child: AppAvatar(
                  imageUrl: avatarUrl,
                  initial: label.isEmpty ? '?' : label[0],
                  size: 56),
            ),
            const SizedBox(height: 7),
            _StoryLabel(label),
          ]),
        ),
      );
}

class _MyStoryItem extends StatelessWidget {
  final String? avatarUrl;
  final bool hasStory;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  const _MyStoryItem(
      {required this.avatarUrl,
      required this.hasStory,
      required this.onTap,
      required this.onAdd});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: hasStory
                          ? AppColors.accentStart
                          : AppColors.hairline2,
                      width: 1.8),
                ),
                child: avatarUrl?.isNotEmpty == true
                    ? AppAvatar(imageUrl: avatarUrl, size: 56)
                    : const Center(child: NightOwlMark(size: 42)),
              ),
            ),
            Positioned(
                right: -2,
                bottom: -2,
                child: Semantics(
                  button: true,
                  label: 'Story нэмэх',
                  child: InkWell(
                    onTap: onAdd,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentStart,
                        border: Border.all(color: AppColors.bgBase, width: 2),
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 15),
                    ),
                  ),
                )),
          ]),
          const SizedBox(height: 7),
          InkWell(onTap: onTap, child: const _StoryLabel('Таны story')),
        ]),
      );
}

class _StoryLabel extends StatelessWidget {
  final String label;
  const _StoryLabel(this.label);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 68,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyXs.copyWith(
              fontSize: 11, height: 1.2, color: AppColors.textSecondary),
        ),
      );
}
