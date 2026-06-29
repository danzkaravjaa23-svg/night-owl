import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../../profile/services/block_report_service.dart';

/// Админ — хэрэглэгч хайх, хориглох / сэргээх
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load(''); // эхэнд сүүлийн хэрэглэгчид
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q));
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      var query = SupabaseService.client
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_banned, is_admin');
      if (q.trim().isNotEmpty) {
        query = query.ilike('username', '%$q%');
      }
      final data = await query.order('created_at', ascending: false).limit(50);
      if (mounted) {
        setState(() {
          _users = (data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBan(Map<String, dynamic> u) async {
    final banned = u['is_banned'] == true;
    final err = await BlockReportService.setBanned(u['id'] as String, !banned);
    if (mounted && err == null) {
      setState(() => u['is_banned'] = !banned);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!banned ? 'Хориглолоо' : 'Сэргээлээ')));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Алдаа: $err'), backgroundColor: AppColors.error));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Хэрэглэгчид', style: AppTextStyles.h2),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: AppColors.textTertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Хэрэглэгч хайх (@username)...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.zero))),
            ]),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accentStart))
              : _users.isEmpty
                  ? Center(child: Text('Хэрэглэгч олдсонгүй',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary)))
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (_, i) => _row(_users[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> u) {
    final uname = (u['username'] as String? ?? 'user').replaceAll('@', '');
    final banned = u['is_banned'] == true;
    final isAdmin = u['is_admin'] == true;
    return ListTile(
      onTap: () => context.push('/creator/${u['id']}'),
      leading: AppAvatar(
        imageUrl: u['avatar_url'] as String?,
        initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?',
        size: 40),
      title: Row(children: [
        Flexible(child: Text('@$uname', style: AppTextStyles.labelMd,
            overflow: TextOverflow.ellipsis)),
        if (isAdmin) ...[
          const SizedBox(width: 6),
          const Icon(Icons.shield, color: AppColors.accentStart, size: 14),
        ],
        if (banned) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text('Хориглосон', style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.error))),
        ],
      ]),
      subtitle: (u['full_name'] as String?)?.isNotEmpty == true
          ? Text(u['full_name'] as String, style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textSecondary))
          : null,
      trailing: isAdmin
          ? null // админыг хориглохгүй
          : TextButton(
              onPressed: () => _toggleBan(u),
              child: Text(banned ? 'Сэргээх' : 'Хориглох',
                  style: AppTextStyles.bodyMd.copyWith(
                      color: banned ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600))),
    );
  }
}
