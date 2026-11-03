import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/widgets/network_video.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';
import '../providers/admin_console_provider.dart';
import '../widgets/admin_widgets.dart';

/// Mounted beneath AdminGate; all pages share guarded pagination and actions.
class AdminRecordsScreen extends ConsumerStatefulWidget {
  final String kind;
  const AdminRecordsScreen({super.key, required this.kind});
  @override
  ConsumerState<AdminRecordsScreen> createState() => _AdminRecordsScreenState();
}

class _AdminRecordsScreenState extends ConsumerState<AdminRecordsScreen> {
  final _search = TextEditingController();
  late final AdminRecordsController _records;
  Timer? _debounce;
  bool _actionOpen = false;
  AdminConsoleAccess get _access => ref.read(adminConsoleAccessProvider)!;
  bool get _content => widget.kind == 'post';
  String get _title => switch (widget.kind) {
        'users' => 'Хэрэглэгчид',
        'reports' => 'Мэдээллүүд',
        'audit' => 'Үйлдлийн түүх',
        _ => 'Контент',
      };
  String get _description => switch (widget.kind) {
        'users' =>
          'Нэрээр хайж, бүртгэлийн төлөв болон баталгаажуулалтыг удирдаарай.',
        'reports' =>
          'Мэдээлэл бүрийн үндэслэлийг шалгаад, шийдвэрээ шалтгаантай нь бүртгээрэй.',
        'audit' =>
          'Админ үйлдэл, хариуцсан хүн болон шийдвэрийн үндэслэлийн түүх.',
        _ =>
          'Нийтлэл, сэтгэгдлийг хайж шалгана. Устгах үйлдэл бүр аудитын түүхэнд үлдэнэ.',
      };

  @override
  void initState() {
    super.initState();
    _records = AdminRecordsController(_access, kind: widget.kind)
      ..addListener(_changed);
    unawaited(_records.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _records.removeListener(_changed);
    _records.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _records.refresh();
  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_records.refresh(query: value));
    });
  }

  Future<void> _action(String action, String targetId, String label,
      {String? reportId}) async {
    if (_actionOpen || _records.loading || !_access.session.isCurrent) return;
    final access = _access;
    setState(() => _actionOpen = true);
    final saved = await showAdminAction(context, access,
        action: action,
        targetId: targetId,
        targetLabel: label,
        reportId: reportId);
    if (!mounted || !access.session.isCurrent) return;
    setState(() => _actionOpen = false);
    if (saved) {
      ref.read(postsVersionProvider.notifier).state++;
      ref.read(socialVersionProvider.notifier).state++;
      ref.invalidate(currentProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Үйлдлийг хадгалж, аудитын түүхэнд бүртгэлээ.')));
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
      title: _title,
      onRefresh: _records.loading || _actionOpen ? null : _refresh,
      child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                AdminIntro(title: _title, subtitle: _description),
                if (widget.kind == 'users' || _content) ...[
                  TextField(
                      controller: _search,
                      onChanged: _searchChanged,
                      maxLength: 100,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) {
                        _debounce?.cancel();
                        _records.refresh(query: value);
                      },
                      decoration: InputDecoration(
                          counterText: '',
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: widget.kind == 'users'
                              ? 'Нэр эсвэл @username'
                              : 'Контентоос хайх',
                          labelText: 'Хайх')),
                  const SizedBox(height: 18),
                ],
                if (widget.kind == 'reports') ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final filter in const [
                      ('pending', 'Хүлээгдэж буй'),
                      ('resolved', 'Шийдвэрлэсэн'),
                      ('reviewed', 'Үндэслэлгүй')
                    ])
                      ChoiceChip(
                          label: Text(filter.$2),
                          selected: _records.status == filter.$1,
                          onSelected: _actionOpen
                              ? null
                              : (_) => _records.refresh(filter: filter.$1))
                  ]),
                  const SizedBox(height: 18),
                ],
                if (_content) ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final filter in const [
                      ('post', 'Нийтлэл'),
                      ('comment', 'Сэтгэгдэл')
                    ])
                      ChoiceChip(
                          label: Text(filter.$2),
                          selected: _records.kind == filter.$1,
                          onSelected: _actionOpen
                              ? null
                              : (_) => _records.refresh(contentKind: filter.$1))
                  ]),
                  const SizedBox(height: 18),
                ],
                if (_records.error != null)
                  AdminMessage(
                      icon: Icons.cloud_off_rounded,
                      title: 'Уншиж чадсангүй',
                      message: _records.error!.message,
                      onRetry: _records.loading
                          ? null
                          : _records.items.isEmpty
                              ? _refresh
                              : _records.loadMore),
                if (_records.loading && _records.items.isEmpty)
                  const AdminLoading(),
                if (!_records.loading &&
                    _records.error == null &&
                    _records.items.isEmpty)
                  AdminMessage(
                      icon: widget.kind == 'reports'
                          ? Icons.task_alt
                          : Icons.search_off,
                      title: widget.kind == 'reports'
                          ? 'Энэ төлөвт мэдээлэл алга'
                          : 'Илэрц олдсонгүй',
                      message: widget.kind == 'reports'
                          ? 'Өөр төлөв сонгох эсвэл дараа дахин шалгаарай.'
                          : widget.kind == 'audit'
                              ? 'Админ үйлдлүүд энд бүртгэгдэнэ.'
                              : 'Хайлтаа өөрчилж дахин оролдоорой.'),
                for (final row in _records.items)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AdminCard(
                          key: ValueKey('admin-${_records.kind}-${row['id']}'),
                          child: switch (widget.kind) {
                            'users' => _user(row),
                            'reports' => _report(row),
                            'audit' => _audit(row),
                            _ => _post(row),
                          })),
                if (_records.items.isNotEmpty && _records.hasMore) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                      onPressed: _records.loading ? null : _records.loadMore,
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                          _records.loading ? 'Уншиж байна…' : 'Цааш үзэх')),
                ],
                const SizedBox(height: 24),
              ])));

  Widget _user(Map<String, dynamic> row) {
    final id = adminText(row, 'id');
    final username = adminText(row, 'username', 'хэрэглэгч')
        .replaceFirst(RegExp(r'^@+'), '');
    final name = adminText(row, 'full_name', '@$username');
    final admin = row['is_admin'] == true;
    final banned = row['is_banned'] == true;
    final verified = row['is_verified'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(
            imageUrl: row['avatar_url'] as String?,
            size: 44,
            initial: name.characters.first),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('@$username', style: AppTextStyles.bodySm)
        ])),
        _menu([
          if (!admin) banned ? 'unban_user' : 'ban_user',
          verified ? 'unverify_user' : 'verify_user'
        ], (action) => _action(action, id, '@$username')),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 7, runSpacing: 7, children: [
        if (admin) const AdminTag('Админ'),
        if (banned) const AdminTag('Хориглосон', warning: true),
        if (verified) const AdminTag('Баталгаажсан'),
        if (!admin && !banned && !verified) const AdminTag('Идэвхтэй'),
      ]),
      const SizedBox(height: 12),
      Text('Бүртгүүлсэн: ${adminDate(row['created_at'])}',
          style: AppTextStyles.bodySm),
      const SizedBox(height: 6),
      TextButton.icon(
          onPressed: () => context.push('/creator/$id'),
          icon: const Icon(Icons.person_outline, size: 18),
          label: const Text('Профайл үзэх')),
    ]);
  }

  Widget _report(Map<String, dynamic> row) {
    final id = adminText(row, 'id');
    final type = adminText(row, 'target_type');
    final target = adminText(row, 'target_id');
    final author = adminText(row, 'target_author_id');
    final pending = row['status'] == 'pending';
    final media = adminText(row, 'target_media_url');
    final reason = switch (row['reason']) {
      'spam' => 'Спам',
      'harassment' => 'Дарамт',
      'nudity' => 'Бэлгийн агуулга',
      'violence' => 'Хүчирхийлэл',
      'hate' => 'Үзэн ядалт',
      'other' => 'Бусад',
      _ => adminText(row, 'reason', 'Мэдээлэл'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(reason, style: AppTextStyles.h3)),
        _menu(
            pending
                ? [
                    'resolve_report',
                    'dismiss_report',
                    if ((type == 'post' || type == 'comment') &&
                        target.isNotEmpty)
                      'delete_$type',
                    if (author.isNotEmpty || type == 'user') 'ban_user'
                  ]
                : ['reopen_report'], (action) {
          if (action == 'ban_user') {
            _action(action, author.isNotEmpty ? author : target,
                'Мэдээлэгдсэн хэрэглэгч',
                reportId: id);
          } else if (action.startsWith('delete_')) {
            _action(action, target,
                adminText(row, 'target_excerpt', 'Мэдээлэгдсэн контент'),
                reportId: id);
          } else {
            _action(action, id, reason);
          }
        }),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AdminTag(switch (type) {
          'post' => 'Нийтлэл',
          'comment' => 'Сэтгэгдэл',
          'story' => 'Story',
          'message' => 'Сонгосон мессеж',
          'group_message' => 'Сонгосон групп мессеж',
          'event' => 'Эвент',
          'review' => 'Газрын үнэлгээ',
          'note' => 'Тэмдэглэл',
          'collection' => 'Цуглуулга',
          'venue' => 'Газар',
          _ => 'Хэрэглэгч'
        }),
        AdminTag(
            pending
                ? 'Хүлээгдэж буй'
                : row['status'] == 'resolved'
                    ? 'Шийдвэрлэсэн'
                    : 'Үндэслэлгүй',
            warning: pending),
      ]),
      const SizedBox(height: 14),
      Text(
          adminText(row, 'target_excerpt',
              'Контентын текст байхгүй эсвэл устсан байна.'),
          style: AppTextStyles.bodyMd.copyWith(height: 1.5)),
      if (media.isNotEmpty) ...[
        const SizedBox(height: 12),
        if (isVideoUrl(media))
          NetworkVideo(
              url: media, height: 240, autoplay: false, showControls: true)
        else
          AuthorizedImage(
              imageUrl: media,
              width: double.infinity,
              height: 220,
              fit: BoxFit.contain),
      ],
      if (adminText(row, 'details').isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Тайлбар', style: AppTextStyles.labelMd),
        const SizedBox(height: 5),
        Text(adminText(row, 'details'),
            style: AppTextStyles.bodyMd.copyWith(height: 1.5))
      ],
      const SizedBox(height: 14),
      Text('Мэдээлсэн: @${adminText(row, 'reporter_username', 'хэрэглэгч')}',
          style: AppTextStyles.bodySm),
      const SizedBox(height: 4),
      Text(adminDate(row['created_at']), style: AppTextStyles.bodySm),
      if (type == 'post' && target.isNotEmpty)
        TextButton.icon(
            onPressed: () => context.push('/post/$target'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Нийтлэл үзэх')),
    ]);
  }

  Widget _post(Map<String, dynamic> row) {
    final body = adminText(row, 'body');
    final media = adminText(row, 'media_url');
    final kind = _records.kind;
    final id = adminText(row, 'id');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text('@${adminText(row, 'username', 'хэрэглэгч')}',
                style: AppTextStyles.h3)),
        _menu(
            ['delete_$kind'],
            (action) =>
                _action(action, id, body.isEmpty ? 'Сонгосон контент' : body)),
      ]),
      Text(adminDate(row['created_at']), style: AppTextStyles.bodySm),
      const SizedBox(height: 14),
      if (body.isNotEmpty)
        Text(body, style: AppTextStyles.bodyMd.copyWith(height: 1.5)),
      if (media.isNotEmpty &&
          !RegExp(r'\.(mp4|mov|webm)(\?|$)', caseSensitive: false)
              .hasMatch(media)) ...[
        const SizedBox(height: 14),
        ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AuthorizedImage(
                imageUrl: media,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(20),
                    child:
                        Text('Медиа нээж чадсангүй. Нийтлэлээс шалгана уу.')))),
      ],
      if (kind == 'post')
        TextButton.icon(
            onPressed: () => context.push('/post/$id'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Нийтлэл үзэх')),
    ]);
  }

  Widget _audit(Map<String, dynamic> row) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.fact_check_outlined, color: AppColors.silver, size: 24),
        const SizedBox(height: 12),
        Text(adminActionLabel(adminText(row, 'action')),
            style: AppTextStyles.h3),
        const SizedBox(height: 8),
        Text(
            '@${adminText(row, 'actor_username', 'админ')} · ${adminDate(row['created_at'])}',
            style: AppTextStyles.bodySm),
        const SizedBox(height: 14),
        Text(adminText(row, 'reason', 'Шалтгаан бүртгэгдээгүй'),
            style: AppTextStyles.bodyMd.copyWith(height: 1.5)),
        const SizedBox(height: 14),
        Text('Холбогдох бүртгэл', style: AppTextStyles.labelMd),
        const SizedBox(height: 5),
        SelectableText(
            '${adminText(row, 'target_type')} · ${adminText(row, 'target_id')}',
            style: AppTextStyles.bodySm),
      ]);

  Widget _menu(List<String> actions, ValueChanged<String> onSelected) =>
      PopupMenuButton<String>(
          tooltip: 'Удирдах үйлдлүүд',
          enabled: !_actionOpen && !_records.loading,
          onSelected: onSelected,
          icon: Icon(Icons.more_horiz_rounded, color: AppColors.textSecondary),
          itemBuilder: (_) => [
                for (final action in actions)
                  PopupMenuItem(
                      value: action,
                      child: Text(adminActionLabel(action),
                          style: AppTextStyles.bodyMd.copyWith(
                              color: action.startsWith('delete_') ||
                                      action == 'ban_user'
                                  ? AppColors.error
                                  : AppColors.textPrimary)))
              ]);
}
