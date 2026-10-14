import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/premium_surface.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../models/user_profile.dart';

/// Profile identity and actions, using the person's actual profile data.
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final Widget avatar;
  final bool coverBusy;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onEditCover;
  final VoidCallback onSettings;
  final VoidCallback onActions;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;

  const ProfileHeader({
    super.key,
    required this.profile,
    required this.avatar,
    required this.onEdit,
    required this.onShare,
    required this.onEditCover,
    required this.onSettings,
    required this.onActions,
    required this.onFollowers,
    required this.onFollowing,
    this.coverBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final username =
        (profile.username?.trim() ?? '').replaceFirst(RegExp(r'^@+'), '');
    final name = profile.name?.trim() ?? '';
    final bio = profile.bio?.trim() ?? '';
    final title = name.isNotEmpty
        ? name
        : username.isNotEmpty
            ? '@$username'
            : 'Профайл';
    final coverHeight = 112 + MediaQuery.paddingOf(context).top;
    final avatarFrame = Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(
              color: AppColors.accentStart.withValues(alpha: .16),
              blurRadius: 20,
              spreadRadius: 1)
        ]),
        child: avatar);
    return AppEntrance(
        child: NightOwlAtmosphere(
            child: Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          // Reserve less height so the avatar overlaps the cover's lower edge.
          height: coverHeight - 24,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: coverHeight,
                child: _ProfileCover(url: profile.coverUrl, busy: coverBusy)),
            Positioned(
                top: 0,
                left: 12,
                right: 12,
                child: SafeArea(
                    bottom: false,
                    child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          _CoverAction(
                              icon: Icons.more_horiz_rounded,
                              label: 'Профайлын үйлдлүүд',
                              onPressed: onActions),
                          const Spacer(),
                          _CoverAction(
                              icon: Icons.settings_outlined,
                              label: 'Тохиргоо',
                              onPressed: onSettings),
                        ])))),
          ]),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (context, constraints) {
                final stats = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: _ProfileStat(
                              count: profile.postsCount, label: 'Пост')),
                      Expanded(
                          child: _ProfileStat(
                              count: profile.followersCount,
                              label: 'Дагагч',
                              onPressed: onFollowers)),
                      Expanded(
                          child: _ProfileStat(
                              count: profile.followingCount,
                              label: 'Дагаж буй',
                              onPressed: onFollowing)),
                    ]);
                if (constraints.maxWidth < 360 &&
                    MediaQuery.textScalerOf(context).scale(19) > 24) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatarFrame,
                        const SizedBox(height: 10),
                        stats
                      ]);
                }
                return Row(children: [
                  avatarFrame,
                  const SizedBox(width: 12),
                  Expanded(child: stats)
                ]);
              }),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Flexible(
                    child: Text(title,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            height: 1.15))),
                if (profile.isVerified) ...[
                  const SizedBox(width: 6),
                  const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Tooltip(
                          message: 'Баталгаажсан профайл',
                          child: Icon(Icons.verified,
                              color: AppColors.accentStart, size: 18))),
                ],
              ]),
              if (name.isNotEmpty && username.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text('@$username',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3)),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(bio,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4)),
              ],
              if (profile.interests.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final interest in profile.interests)
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: AppColors.bgSurface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.hairline)),
                        child: Text(interest,
                            style: TextStyle(
                                color: AppColors.silver,
                                fontSize: 12,
                                height: 1.3))),
                ]),
              ],
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final edit = PressFeedback(
                    child: FilledButton.icon(
                        onPressed: onEdit,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentStart,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        icon: const SculptedIcon(Icons.edit_outlined,
                            size: 17, color: Colors.white, onDark: true),
                        label: const Text('Профайл засах',
                            textAlign: TextAlign.center)));
                final share = PressFeedback(
                    child: OutlinedButton.icon(
                        onPressed: onShare,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size.fromHeight(44),
                            side: BorderSide(color: AppColors.hairline2),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        icon: SculptedIcon(Icons.ios_share_rounded,
                            size: 17, color: AppColors.textPrimary),
                        label: const Text('Хуваалцах',
                            textAlign: TextAlign.center)));
                if (constraints.maxWidth < 360 &&
                    MediaQuery.textScalerOf(context).scale(13) > 17) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [edit, const SizedBox(height: 8), share]);
                }
                return Row(children: [
                  Expanded(child: edit),
                  const SizedBox(width: 8),
                  Expanded(child: share)
                ]);
              }),
            ])),
      ]),
      // Keep the entire cover-edit target hittable across the overlapping edge.
      Positioned(
          right: 12,
          top: coverHeight - 54,
          child: _CoverAction(
              icon: Icons.photo_camera_outlined,
              label: 'Нүүр зураг солих',
              onPressed: coverBusy ? null : onEditCover)),
    ])));
  }
}

class ProfileContentTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const ProfileContentTabs(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: AppColors.hairline),
                bottom: BorderSide(color: AppColors.hairline))),
        child: Stack(children: [
          IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                for (final entry
                    in ['Нийтлэл', 'Хадгалсан', 'Бичлэг'].asMap().entries)
                  Expanded(
                      child: Semantics(
                    button: true,
                    selected: selected == entry.key,
                    child: PressFeedback(
                        child: InkWell(
                      onTap: () => onChanged(entry.key),
                      child: AnimatedContainer(
                        duration:
                            AppMotion.duration(context, AppMotion.release),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 10),
                        color: selected == entry.key
                            ? AppColors.accentStart.withValues(alpha: .07)
                            : Colors.transparent,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          SculptedIcon(
                              [
                                Icons.grid_on_rounded,
                                Icons.bookmark_border_rounded,
                                Icons.play_circle_outline_rounded
                              ][entry.key],
                              size: 21,
                              color: selected == entry.key
                                  ? AppColors.silver
                                  : AppColors.textTertiary),
                          const SizedBox(height: 4),
                          Text(entry.value,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: selected == entry.key
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    )),
                  )),
              ])),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedAlign(
                  alignment: Alignment(selected - 1.0, 0),
                  duration: AppMotion.duration(
                      context, const Duration(milliseconds: 380)),
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                      widthFactor: 1 / 3,
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: AppColors.purpleGradient,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.accentStart
                                      .withValues(alpha: .24),
                                  blurRadius: 8)
                            ]),
                      )),
                ),
              )),
        ]),
      );
}

class _ProfileStat extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback? onPressed;
  const _ProfileStat(
      {required this.count, required this.label, this.onPressed});

  String get formatted {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(formatted,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.2)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.3)),
        ]));
    return onPressed == null
        ? content
        : InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: content);
  }
}

class _CoverAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _CoverAction({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => PressFeedback(
      enabled: onPressed != null,
      child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          style: IconButton.styleFrom(
              backgroundColor: const Color(0x450B0D17),
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44)),
          icon:
              SculptedIcon(icon, size: 22, color: Colors.white, onDark: true)));
}

class _ProfileCover extends StatelessWidget {
  final String? url;
  final bool busy;
  const _ProfileCover({this.url, required this.busy});

  Widget _fallback() => Image.asset('assets/images/tonight_city.png',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.15),
      errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.bgElevated));

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 112,
      child: Stack(fit: StackFit.expand, children: [
        if (url?.isNotEmpty == true)
          CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: 1200,
              placeholder: (_, __) => ColoredBox(color: AppColors.bgElevated),
              errorWidget: (_, __, ___) => _fallback())
        else
          _fallback(),
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [
              0,
              0.6,
              1
            ],
                    colors: [
              const Color(0x240B0D17),
              AppColors.bgBase.withValues(alpha: 0.12),
              AppColors.bgBase
            ]))),
        if (busy)
          const Center(
              child: OwlLoading(
                  size: 32,
                  compact: true,
                  onDark: true,
                  message: 'Нүүр зургийг хадгалж байна')),
      ]));
}
