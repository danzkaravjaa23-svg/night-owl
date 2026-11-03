import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/account_deletion_service.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  late final String? _owner;
  bool _acknowledged = false;
  bool _busy = false;
  bool _sending = false;
  bool _scopeChanged = false;
  bool _deleted = false;
  String? _message;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(sessionUserIdProvider);
  }

  bool _active(int epoch) =>
      mounted &&
      !_scopeChanged &&
      epoch == _epoch &&
      ref.read(sessionUserIdProvider) == _owner;

  Future<void> _delete() async {
    if (_busy || !_acknowledged || _owner == null || _scopeChanged) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Бүрмөсөн устгах уу?'),
              content: const Text(
                  'Бүртгэл, холбоотой контент болон хувийн медиагаа устгана. Буцаах боломжгүй.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Цуцлах')),
                TextButton(
                    key: const ValueKey('delete-account-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Бүрмөсөн устгах',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              ],
            ));
    if (!_active(epoch)) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    final service = ref.read(accountDeletionServiceProvider);
    try {
      await service.deleteOwnAccount(_owner);
      if (!_active(epoch)) return;
      setState(() {
        _deleted = true;
        _acknowledged = false;
        _message = null;
      });
      final cleared = await service.clearDeletedSession(_owner);
      if (!mounted || _scopeChanged || epoch != _epoch) return;
      if (!cleared) {
        setState(() => _message =
            'Бүртгэл устсан. Нэвтрэх төлөвийг цэвэрлэхийн тулд аппыг дахин нээнэ үү.');
      }
    } catch (error) {
      if (!_active(epoch)) return;
      setState(() {
        _acknowledged = false;
        _message = error is AccountDeletionFailure
            ? error.message
            : const AccountDeletionFailure('unknown').message;
      });
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(sessionUserIdProvider, (previous, next) {
      if (next == _owner || (_deleted && next == null)) return;
      setState(() {
        _epoch++;
        _scopeChanged = true;
        _acknowledged = false;
        _busy = false;
        _sending = false;
        _message = null;
      });
    });
    final current = ref.watch(sessionUserIdProvider);
    final changed =
        _scopeChanged || (current != _owner && !(_deleted && current == null));
    final profile = !changed && !_deleted && _owner != null
        ? ref.watch(currentProfileProvider).valueOrNull
        : null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Бүртгэл устгах'),
            leading: IconButton(
                tooltip: 'Буцах',
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy
                    ? null
                    : () => context.canPop()
                        ? context.pop()
                        : context.go(_owner == null
                            ? AppRoutes.authLanding
                            : AppRoutes.settings))),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          if (changed) ...[
            const Text('Бүртгэл солигдлоо. Устгах хуудсыг дахин нээнэ үү.'),
          ] else if (_deleted) ...[
            const Icon(Icons.check_circle_outline, size: 40),
            const SizedBox(height: 16),
            const Text('Бүртгэл устгагдлаа.'),
            if (_message != null) Text(_message!),
            const SizedBox(height: 20),
            FilledButton(
                onPressed:
                    _busy ? null : () => context.go(AppRoutes.authLanding),
                child: const Text('Нэвтрэх хуудас')),
          ] else if (_owner == null) ...[
            const Text('Өөрийн бүртгэлийг устгахын тулд нэвтэрнэ үү.'),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => context.go(Uri(
                        path: AppRoutes.authLanding,
                        queryParameters: {'next': AppRoutes.deleteAccount})
                    .toString()),
                child: const Text('Нэвтрэх')),
          ] else ...[
            Text(
                profile == null
                    ? 'Таны нэвтэрсэн бүртгэл'
                    : '@${profile.username}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text(
                'Бүртгэл болон түүнтэй холбоотой пост, story, reel, сэтгэгдэл, мессеж, хадгалсан газар, хувийн медиагаа бүрмөсөн устгах хүсэлт илгээнэ.'),
            const SizedBox(height: 12),
            const Text(
                'Устгасан мэдээллийг буцааж сэргээх боломжгүй. Бусдын өмнө татсан эсвэл хуулсан файлыг буцаан арилгах боломжгүй.'),
            const SizedBox(height: 12),
            const Text(
                'Зөвхөн сервер устгал дууссаныг баталсан үед амжилттай гэж мэдээлнэ. Сүлжээ тасарвал устгал үргэлжилсэн байж болно.'),
            const SizedBox(height: 20),
            CheckboxListTile(
                key: const ValueKey('delete-account-ack'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Бүртгэлээ бүрмөсөн устгах үр дагаврыг ойлголоо'),
                value: _acknowledged,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _acknowledged = value == true)),
            if (_sending) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Хүсэлт боловсруулж байна...'),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(_message!)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
                key: const ValueKey('delete-account-submit'),
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: _busy || !_acknowledged ? null : _delete,
                icon: const Icon(Icons.person_remove_outlined),
                label:
                    const Text('Бүртгэл устгах', textAlign: TextAlign.center)),
          ],
        ])),
      ),
    );
  }
}
