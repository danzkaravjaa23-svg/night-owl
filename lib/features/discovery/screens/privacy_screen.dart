import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/settings_rows.dart';
import '../services/discovery_service.dart';
import 'discovery_screen.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;
  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(privacyProvider);
      ref.read(socialVersionProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: const AppHeader.title(
          title: 'Нууцлал, хүсэлтүүд',
          compact: true,
          fallbackLocation: '/profile'),
      body: ref.watch(privacyProvider).when(
          loading: () => const Center(child: OwlLoading()),
          error: (e, _) => DiscoveryProblem(
              error: e, retry: () => ref.invalidate(privacyProvider)),
          data: (settings) {
            final isPrivate = settings['is_private'] == true;
            Future<void> setPrivate(bool value) => _change(() => ref
                .read(discoveryServiceProvider)
                .setPrivacy(
                    private: value,
                    messages: settings['dm_policy'] as String));
            // Same rhythm as Settings: 28 between sections, 12 label → card.
            return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.x3, AppSpacing.page, AppSpacing.x8),
                children: [
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.x3),
                        child: LinearProgressIndicator()),
                  SettingsCard(children: [
                    SettingsRow(
                        icon: Icons.lock_outline,
                        title: 'Хувийн профайл',
                        subtitle:
                            'Нийтлэл, цуглуулгыг зөвхөн зөвшөөрсөн дагагчид үзнэ',
                        enabled: !_busy,
                        onTap: () => setPrivate(!isPrivate),
                        trailing: SettingsSwitch(
                            value: isPrivate,
                            onChanged: _busy ? null : setPrivate)),
                    const SettingsDivider(),
                    Padding(
                        padding: const EdgeInsets.all(10),
                        child: InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'Хэн мессеж бичих вэ?'),
                            child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                    // A rejected write keeps the persisted policy visible,
                                    // even when it completes before the next frame.
                                    value: settings['dm_policy'] as String,
                                    isExpanded: true,
                                    itemHeight: null,
                                    // Popup цэс шиг: bgElevated, 14 px булан.
                                    borderRadius: AppRadii.mdR,
                                    dropdownColor: AppColors.bgElevated,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'requests',
                                          child: Text(
                                              'Танихгүй хүнээс хүсэлт авах')),
                                      DropdownMenuItem(
                                          value: 'following',
                                          child: Text(
                                              'Зөвхөн миний дагадаг хүмүүс')),
                                      DropdownMenuItem(
                                          value: 'nobody',
                                          child: Text('Хэн ч бичихгүй')),
                                      DropdownMenuItem(
                                          value: 'everyone',
                                          child: Text('Бүх хүн'))
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (v) {
                                            if (v != null) {
                                              _change(() => ref
                                                  .read(
                                                      discoveryServiceProvider)
                                                  .setPrivacy(
                                                      private: isPrivate,
                                                      messages: v));
                                            }
                                          })))),
                  ]),
                  const SizedBox(height: 28),
                  const SettingsSectionLabel('Дагах хүсэлтүүд'),
                  const SizedBox(height: AppSpacing.x3),
                  ref.watch(followRequestsProvider).when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => DiscoveryProblem(
                          error: e,
                          retry: () => ref.invalidate(followRequestsProvider)),
                      // Kit мөрүүдийн 10 px дотор зай, 12 px icon зай: карт
                      // өөрөө 6 px-ээр шахсан тул нэр бүтэн уншигдана.
                      data: (requests) => SettingsCard(children: [
                            if (requests.isEmpty)
                              const ListTile(
                                  contentPadding: EdgeInsetsDirectional.only(
                                      start: 10, end: 10),
                                  title: Text('Шинэ хүсэлт алга')),
                            for (final row in requests)
                              ListTile(
                                  contentPadding:
                                      const EdgeInsetsDirectional.only(
                                          start: 10, end: 2),
                                  horizontalTitleGap: 12,
                                  leading: AppAvatar(
                                      imageUrl: (row['profiles']
                                          as Map?)?['avatar_url'] as String?,
                                      initial: '?',
                                      size: 44),
                                  title: Text((row['profiles']
                                          as Map?)?['username'] as String? ??
                                      'Хэрэглэгч'),
                                  trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                            tooltip: 'Татгалзах',
                                            onPressed: _busy
                                                ? null
                                                : () => _change(() => ref
                                                    .read(
                                                        discoveryServiceProvider)
                                                    .respondFollow(
                                                        row['requester_id']
                                                            as String,
                                                        false)),
                                            icon: const Icon(AppIcons.close)),
                                        IconButton(
                                            tooltip: 'Зөвшөөрөх',
                                            onPressed: _busy
                                                ? null
                                                : () => _change(() => ref
                                                    .read(
                                                        discoveryServiceProvider)
                                                    .respondFollow(
                                                        row['requester_id']
                                                            as String,
                                                        true)),
                                            icon: const Icon(Icons.check))
                                      ]))
                          ])),
                ]);
          }));
}
