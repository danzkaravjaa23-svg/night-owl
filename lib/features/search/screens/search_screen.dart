import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _explore = [];
  bool _loading = false;
  Timer? _debounce;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  Future<void> _loadExplore() async {
    try {
      final data = await SupabaseService.client.from('posts')
          .select('id, media_url, likes_count')
          .order('created_at', ascending: false).limit(30);
      if (mounted) setState(() => _explore = (data as List).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  // Товчлуур дарах бүрт query явуулахгүй — 300мс хүлээж debounce хийнэ
  void _search(String q) {
    setState(() { _q = q; });
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _users = []; _venues = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    try {
      final u = await SupabaseService.client.from('profiles')
          .select('id, username, full_name, avatar_url, is_verified')
          .ilike('username', '%$q%')
          .eq('is_banned', false).limit(20);
      final v = await SupabaseService.client.from('venues')
          .select('id, name, district, venue_type')
          .ilike('name', '%$q%').limit(20);
      if (mounted) setState(() {
        _users = (u as List).cast<Map<String, dynamic>>().where((p) => p['id'] != _myId).toList();
        _venues = (v as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final searching = _q.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 16, 8),
          child: Row(children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 20, color: AppColors.textPrimary)),
            Expanded(child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline)),
              child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _ctrl, autofocus: true, onChanged: _search,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Хүн, газар хайх...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.zero))),
              if (_q.isNotEmpty)
                GestureDetector(
                  onTap: () { _ctrl.clear(); _search(''); },
                  child: const Padding(padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.close, color: AppColors.textTertiary, size: 16))),
            ]),
            )),
          ]),
        ),
        Expanded(child: searching ? _results() : _exploreGrid()),
      ])),
    );
  }

  Widget _results() {
    if (_loading) return const Center(child: CircularProgressIndicator(
      color: AppColors.accentStart, strokeWidth: 2));
    if (_users.isEmpty && _venues.isEmpty) {
      return Center(child: Text('Илэрц олдсонгүй',
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)));
    }
    return ListView(children: [
      if (_users.isNotEmpty) ...[
        _sectionLabel('ХҮМҮҮС'),
        for (final u in _users) _userTile(u),
      ],
      if (_venues.isNotEmpty) ...[
        _sectionLabel('ГАЗРУУД'),
        for (final v in _venues) _venueTile(v),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Text(t, style: AppTextStyles.labelSm.copyWith(
      color: AppColors.textSecondary, letterSpacing: 0.8)));

  Widget _userTile(Map<String, dynamic> u) {
    final uname = (u['username'] as String? ?? 'User').replaceAll('@', '');
    return ListTile(
      onTap: () => context.push('/creator/${u['id']}'),
      leading: AppAvatar(imageUrl: u['avatar_url'] as String?,
        initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?', size: 44),
      title: Row(children: [
        Text('@$uname', style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
        if (u['is_verified'] == true) ...[
          const SizedBox(width: 4),
          const Icon(Icons.verified, color: AppColors.accentStart, size: 14),
        ],
      ]),
      subtitle: (u['full_name'] as String?)?.isNotEmpty == true
        ? Text(u['full_name'] as String,
            style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))
        : null,
    );
  }

  Widget _venueTile(Map<String, dynamic> v) => ListTile(
    onTap: () => context.push('/venue/reviews/${v['id']}'),
    leading: Container(width: 44, height: 44,
      decoration: const BoxDecoration(shape: BoxShape.circle,
        gradient: AppColors.accentGradientSoft),
      child: const Center(child: Icon(Icons.location_on, color: Colors.white, size: 20))),
    title: Text(v['name'] as String? ?? '',
      style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
    subtitle: (v['district'] as String?)?.isNotEmpty == true
      ? Text(v['district'] as String,
          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))
      : null,
  );

  Widget _exploreGrid() {
    if (_explore.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      padding: const EdgeInsets.all(1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
      itemCount: _explore.length,
      itemBuilder: (_, i) {
        final p = _explore[i];
        final url = p['media_url'] as String?;
        final isVideo = isVideoUrl(url);
        return GestureDetector(
          onTap: () => context.push('/post/${p['id']}'),
          child: Stack(fit: StackFit.expand, children: [
            if (url != null && !isVideo)
              CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.bgSurface),
                errorWidget: (_, __, ___) => Container(color: AppColors.bgSurface,
                  child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.textTertiary)))
            else if (isVideo && url != null)
              // Видеоны эхний кадрыг cover болгож харуулна (+ play icon)
              NetworkVideo(url: url, posterOnly: true)
            else
              Container(color: AppColors.bgSurface),
          ]),
        );
      },
    );
  }
}
