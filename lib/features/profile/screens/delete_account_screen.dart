import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/settings_rows.dart';
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
        builder: (dialogContext) => AlertDialog(
              title: const Text('Бүрмөсөн устгах уу?'),
              content: const Text(
                  'Бүртгэл, холбоотой контент болон хувийн медиагаа устгана. Буцаах боломжгүй.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Цуцлах')),
                // Устгах баталгаа — dangerFill дээр цагаан (DS-03)
                FilledButton(
                    key: const ValueKey('delete-account-confirm'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.dangerFill,
                        foregroundColor: Colors.white),
                    // Нарийн дэлгэц + том фонтод 2 мөр болоход ч төвдөө.
                    child: const Text('Бүрмөсөн устгах',
                        textAlign: TextAlign.center)),
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
    // DS-05: апп-ын token (AppColors, AppTextStyles, AppSpacing).
    final body = AppTextStyles.bodyMd
        .copyWith(color: AppColors.textSecondary, height: 1.5);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppHeader.title(
            title: 'Бүртгэл устгах',
            // Устгал явж байхад буцахгүй (PopScope ч мөн хаана)
            onBack: () {
              if (_busy) return;
              AppHeader.goBack(context,
                  fallbackLocation: _owner == null
                      ? AppRoutes.authLanding
                      : AppRoutes.settings);
            }),
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.x3, AppSpacing.page, AppSpacing.x8),
                children: [
          if (changed) ...[
            Text('Бүртгэл солигдлоо. Устгах хуудсыг дахин нээнэ үү.',
                style: AppTextStyles.bodyMd),
          ] else if (_deleted) ...[
            Icon(Icons.check_circle_outline,
                size: 40, color: AppColors.success),
            const SizedBox(height: AppSpacing.x4),
            Text('Бүртгэл устгагдлаа.', style: AppTextStyles.title),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(_message!, style: body),
            ],
            const SizedBox(height: AppSpacing.x5),
            GradientButton(
                label: 'Нэвтрэх хуудас',
                onPressed:
                    _busy ? null : () => context.go(AppRoutes.authLanding)),
          ] else if (_owner == null) ...[
            Text('Өөрийн бүртгэлийг устгахын тулд нэвтэрнэ үү.',
                style: AppTextStyles.bodyMd),
            const SizedBox(height: AppSpacing.x4),
            GradientButton(
                label: 'Нэвтрэх',
                onPressed: () => context.go(Uri(
                        path: AppRoutes.authLanding,
                        queryParameters: {'next': AppRoutes.deleteAccount})
                    .toString())),
          ] else ...[
            // Аль бүртгэлийг устгаж буйг тод харуулна (settings kit).
            SettingsCard(children: [
              SettingsRow(
                  icon: AppIcons.profile,
                  title: profile == null
                      ? 'Таны нэвтэрсэн бүртгэл'
                      : '@${profile.username}'),
            ]),
            const SizedBox(height: AppSpacing.x5),
            Text(
                'Бүртгэл болон түүнтэй холбоотой пост, story, reel, сэтгэгдэл, мессеж, хадгалсан газар, хувийн медиагаа бүрмөсөн устгах хүсэлт илгээнэ.',
                style: body),
            const SizedBox(height: AppSpacing.x3),
            Text(
                'Устгасан мэдээллийг буцааж сэргээх боломжгүй. Бусдын өмнө татсан эсвэл хуулсан файлыг буцаан арилгах боломжгүй.',
                style: body),
            const SizedBox(height: AppSpacing.x3),
            Text(
                'Зөвхөн сервер устгал дууссаныг баталсан үед амжилттай гэж мэдээлнэ. Сүлжээ тасарвал устгал үргэлжилсэн байж болно.',
                style: body),
            const SizedBox(height: AppSpacing.x5),
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
              const SizedBox(height: AppSpacing.x3),
              Text('Хүсэлт боловсруулж байна...',
                  style: AppTextStyles.bodySm),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.x4),
              // Энэ төлөвт мессеж нь үргэлж алдаа — danger өнгө (DS-01)
              Semantics(
                  liveRegion: true,
                  child: Text(_message!,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.danger, height: 1.5))),
            ],
            const SizedBox(height: AppSpacing.x5),
            // Устгах үйлдэл — dangerFill дээр цагаан (DS-03)
            FilledButton.icon(
                key: const ValueKey('delete-account-submit'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.dangerFill,
                    foregroundColor: Colors.white),
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
