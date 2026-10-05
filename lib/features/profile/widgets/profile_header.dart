import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../models/user_profile.dart';

/// Profile identity and actions, using the person's actual profile data.
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final Widget avatar;
  final bool coverBusy;
  final VoidCallback onEdit;
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
    required this.onEditCover,
    required this.onSettings,
    required this.onActions,
    required this.onFollowers,
    required this.onFollowing,
    this.coverBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final username = profile.username?.trim() ?? '';
    final name = profile.name?.trim() ?? '';
    final bio = profile.bio?.trim() ?? '';
    return Column(children: [
      SizedBox(
        height: 246,
        width: double.infinity,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ProfileCover(
                  url: profile.coverUrl, busy: coverBusy, onEdit: onEditCover)),
          Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _CoverAction(
                                icon: Icons.more_horiz_rounded,
                                label: 'Профайлын үйлдлүүд',
                                onPressed: onActions),
                            _CoverAction(
                                icon: Icons.settings_outlined,
                                label: 'Тохиргоо',
                                onPressed: onSettings),
                          ])))),
          avatar,
        ]),
      ),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(children: [
            Text(username.isEmpty ? 'Профайл' : username,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.2)),
            if (name.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4)),
            ],
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(bio,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.55))),
            ],
            if (profile.interests.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(profile.interests.join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.silver, fontSize: 12, height: 1.5)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onEdit,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentStart,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                icon: const SculptedIcon(Icons.edit_outlined,
                    size: 17, color: Colors.white, onDark: true),
                label:
                    const Text('Профайл засах', textAlign: TextAlign.center)),
            const SizedBox(height: 24),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Row(
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
                    ])),
            const SizedBox(height: 20),
          ])),
    ]);
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
            border: Border(top: BorderSide(color: AppColors.hairline))),
        child: IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final entry
              in ['Нийтлэл', 'Хадгалсан', 'Бичлэг'].asMap().entries)
            Expanded(
                child: Semantics(
                    button: true,
                    selected: selected == entry.key,
                    child: InkWell(
                        onTap: () => onChanged(entry.key),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 16),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        width: 2,
                                        color: selected == entry.key
                                            ? AppColors.accentStart
                                            : Colors.transparent))),
                            child: Text(entry.value,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: selected == entry.key
                                        ? AppColors.textPrimary
                                        : AppColors.textTertiary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)))))),
        ])),
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
          const SizedBox(height: 5),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 12, height: 1.3)),
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
  Widget build(BuildContext context) => IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
          backgroundColor: const Color(0x450B0D17),
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 44)),
      icon: SculptedIcon(icon, size: 22, color: Colors.white, onDark: true));
}

class _ProfileCover extends StatelessWidget {
  final String? url;
  final bool busy;
  final VoidCallback onEdit;
  const _ProfileCover({this.url, required this.busy, required this.onEdit});

  Widget _fallback() => Image.asset('assets/images/tonight_city.png',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.15),
      errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.bgElevated));

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 186,
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
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))),
        Positioned(
            right: 12,
            bottom: 10,
            child: _CoverAction(
                icon: Icons.photo_camera_outlined,
                label: 'Cover зураг солих',
                onPressed: busy ? null : onEdit)),
      ]));
}
