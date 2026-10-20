import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_avatar.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';
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
      appBar: AppBar(
          leading: const DiscoveryBackButton(fallback: '/profile'),
          title: const Text('Нууцлал, хүсэлтүүд')),
      body: ref.watch(privacyProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => DiscoveryProblem(
              error: e, retry: () => ref.invalidate(privacyProvider)),
          data: (settings) => ListView(children: [
                if (_busy) const LinearProgressIndicator(),
                SwitchListTile(
                    title: const Text('Хувийн профайл'),
                    subtitle: const Text(
                        'Нийтлэл, цуглуулгыг зөвхөн зөвшөөрсөн дагагчид үзнэ'),
                    value: settings['is_private'] == true,
                    onChanged: _busy
                        ? null
                        : (v) => _change(() => ref
                            .read(discoveryServiceProvider)
                            .setPrivacy(
                                private: v,
                                messages: settings['dm_policy'] as String))),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String>(
                        initialValue: settings['dm_policy'] as String,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                            labelText: 'Хэн мессеж бичих вэ?'),
                        items: const [
                          DropdownMenuItem(
                              value: 'requests',
                              child: Text('Танихгүй хүнээс хүсэлт авах')),
                          DropdownMenuItem(
                              value: 'following',
                              child: Text('Зөвхөн миний дагадаг хүмүүс')),
                          DropdownMenuItem(
                              value: 'nobody', child: Text('Хэн ч бичихгүй')),
                          DropdownMenuItem(
                              value: 'everyone', child: Text('Бүх хүн'))
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                                if (v != null) {
                                  _change(() => ref
                                      .read(discoveryServiceProvider)
                                      .setPrivacy(
                                          private:
                                              settings['is_private'] == true,
                                          messages: v));
                                }
                              })),
                const Divider(),
                const ListTile(title: Text('Дагах хүсэлтүүд')),
                ref.watch(followRequestsProvider).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => DiscoveryProblem(
                        error: e,
                        retry: () => ref.invalidate(followRequestsProvider)),
                    data: (requests) => Column(children: [
                          if (requests.isEmpty)
                            const ListTile(title: Text('Шинэ хүсэлт алга')),
                          for (final row in requests)
                            ListTile(
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
                                          icon: const Icon(Icons.close)),
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
              ])));
}
