import '../../../core/widgets/content_review_notice.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/widgets/gradient_button.dart';
import '../providers/event_provider.dart';
import '../../post/services/content_publication.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  final EventService? service;
  final Future<Uint8List?> Function()? coverPicker;
  const CreateEventScreen({super.key, this.service, this.coverPicker});
  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String? _venueId;
  String? _venueName;
  DateTime? _when;
  Uint8List? _cover;
  bool _busy = false;
  String? _error;

  late final EventService _service;
  late final PublicationSession _session;
  StreamSubscription<void>? _authSubscription;
  bool _invalidated = false;
  int _sessionRevision = 0;
  bool _picking = false;
  bool _allowExit = false;
  Map<String, dynamic>? _pendingRow;
  String? _status;
  bool get _canEdit =>
      !_invalidated && !_busy && !_picking && _pendingRow == null;
  bool get _hasDraft =>
      _cover != null ||
      _when != null ||
      _venueId != null ||
      _titleCtrl.text.isNotEmpty ||
      _descCtrl.text.isNotEmpty ||
      _priceCtrl.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ref.read(eventServiceProvider);
    _session = _service.captureSession();
    _authSubscription = _service.sessionChanges.listen((_) => _checkSession(),
        onError: (Object _) => _invalidateSession());
    for (final controller in [_titleCtrl, _descCtrl, _priceCtrl]) {
      controller.addListener(_draftChanged);
    }
  }

  void _checkSession() {
    if (!_session.isCurrent) _invalidateSession();
  }

  void _invalidateSession() {
    if (!mounted || _invalidated) return;
    setState(() {
      _invalidated = true;
      _sessionRevision++;
      _cover = null;
      _when = null;
      _venueId = null;
      _venueName = null;
      _pendingRow = null;
      _busy = false;
      _picking = false;
    });
    _titleCtrl.clear();
    _descCtrl.clear();
    _priceCtrl.clear();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _showFailure(Object error, String fallback) {
    if (mounted) {
      setState(() =>
          _error = error is PublicationFailure ? error.message : fallback);
    }
  }

  Future<void> _pickVenue() async {
    if (!_canEdit) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      _session.check();
      final v = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: AppColors.bgElevated,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadii.xl))),
        builder: (_) => _VenuePick(service: _service, session: _session),
      );
      if (!mounted) return;
      _session.check();
      if (v != null) {
        setState(() {
          _venueId = v['id'] as String;
          _venueName = v['name'] as String;
        });
      }
    } catch (error) {
      _showFailure(error, 'Газар сонгож чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickDateTime() async {
    if (!_canEdit) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      _session.check();
      final now = DateTime.now();
      final last = now.add(const Duration(days: 365));
      final initial =
          _when != null && _when!.isAfter(now) && _when!.isBefore(last)
              ? _when!
              : now;
      final d = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: now,
          lastDate: last);
      if (d == null || !mounted) return;
      _session.check();
      final t = await showTimePicker(
          context: context,
          initialTime: _when == null
              ? const TimeOfDay(hour: 21, minute: 0)
              : TimeOfDay.fromDateTime(_when!));
      if (t == null || !mounted) return;
      _session.check();
      final selected = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (!selected.isAfter(DateTime.now())) {
        throw const PublicationFailure(
            'Эвент эхлэх огноо, цаг ирээдүйд байх ёстой');
      }
      setState(() => _when = selected);
    } catch (error) {
      _showFailure(error, 'Огноо сонгож чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickCover() async {
    if (!_canEdit) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      _session.check();
      final bytes =
          await (widget.coverPicker ?? ImageUploader.pickBytesFromGallery)();
      if (!mounted) return;
      _session.check();
      if (bytes == null) return;
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw const PublicationFailure(
            'Зураг хоосон эсвэл 25MB-ээс том байна.');
      }
      // Decode before replacing the previous valid cover, preserving that draft on failure.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1080);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      _session.check();
      setState(() => _cover = bytes);
    } catch (error) {
      _showFailure(
          error, 'Зургийг нээж чадсангүй. JPG эсвэл PNG зураг сонгоно уу.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_invalidated || _busy || _picking) return;
    try {
      _session.check();
      final draft = _pendingRow ??
          eventDraft(
              id: ContentPublicationService.newId(),
              ownerId: _session.ownerId!,
              title: _titleCtrl.text,
              description: _descCtrl.text,
              venueId: _venueId,
              startsAt: _when,
              price: _priceCtrl.text,
              now: DateTime.now());
      final cover = _cover;
      setState(() {
        _busy = true;
        _error = null;
        _status = 'Эвент нийтэлж байна…';
      });
      if (_pendingRow == null) {
        String? coverUrl;
        if (cover != null) {
          setState(() => _status = 'Зураг илгээж байна…');
          final prepared = await _service.prepareStoryImage(cover);
          if (!mounted) return;
          _session.check();
          final type = ContentPublicationService.imageType(prepared);
          coverUrl = await _service.uploadPost(_session, prepared,
              path: '${_session.ownerId}/event_${draft['id']}.${type.ext}',
              contentType: type.mime);
          if (!mounted) return;
          _session.check();
        }
        _pendingRow = Map.unmodifiable(
            {...draft, if (coverUrl != null) 'cover_url': coverUrl});
      }
      setState(() => _status = 'Эвентийн төлөвийг баталгаажуулж байна…');
      await _service.publishEvent(_session, _pendingRow!);
      if (!mounted) return;
      _session.check();
      // Events stay pre-moderated: never claim they are already public.
      showPublicationFeedback(context, SavedContentKind.event, null);
      ref.invalidate(upcomingEventsProvider);
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_invalidated && _session.isCurrent) _close();
      });
    } catch (error) {
      _showFailure(
          error, 'Эвент нийтэлж чадсангүй. Ноорог энэ дэлгэцэд хэвээр байна.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _requestClose() async {
    if (_busy || _picking) return;
    final revision = _sessionRevision;
    final wasCurrent = _session.isCurrent;
    if (_hasDraft) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Нооргоос гарах уу?'),
                content: Text(_pendingRow == null
                    ? 'Энэ дэлгэцээс гарахад эвентийн ноорог хадгалагдахгүй.'
                    : 'Нийтлэгдсэн байж болно. Эвентүүдээ шалгана уу; гарснаар серверийн хүсэлт цуцлагдахгүй.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Үргэлжлүүлэх')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Гарах'))
                ],
              ));
      if (!mounted ||
          discard != true ||
          revision != _sessionRevision ||
          (wasCurrent && !_session.isCurrent)) {
        return;
      }
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          revision == _sessionRevision &&
          (!wasCurrent || _session.isCurrent)) {
        _close();
      }
    });
  }

  void _close() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.feed);

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    _session.close();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whenStr = _when == null
        ? 'Огноо · цаг сонгох'
        : '${_when!.year}/${_when!.month}/${_when!.day}  '
            '${_when!.hour.toString().padLeft(2, '0')}:${_when!.minute.toString().padLeft(2, '0')}';
    return PopScope(
        canPop:
            _allowExit || _invalidated || (!_hasDraft && !_busy && !_picking),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _requestClose();
        },
        child: Scaffold(
          backgroundColor: AppColors.bgBase,
          appBar: AppBar(
            backgroundColor: AppColors.bgBase,
            elevation: 0,
            leading: IconButton(
                tooltip: 'Хаах',
                onPressed: (_busy || _picking) ? null : _requestClose,
                icon: Icon(Icons.close, color: AppColors.textPrimary)),
            title: Text('Эвент нэмэх', style: AppTextStyles.h2),
          ),
          body: _invalidated
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Нэвтрэх хаяг өөрчлөгдсөн тул өмнөх нооргийг хаалаа. Энэ дэлгэцээс гараад шинэ эвент нээнэ үү.',
                          textAlign: TextAlign.center)))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
                  children: [
                      if (_picking)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('Сонголтыг хүлээж байна…')),
                      // Cover
                      _Tap(
                        onTap: _canEdit ? _pickCover : null,
                        child: Container(
                            height: 150,
                            decoration: BoxDecoration(
                                color: AppColors.bgElevated,
                                borderRadius: AppRadii.mdR,
                                border: Border.all(color: AppColors.hairline),
                                image: _cover != null
                                    ? DecorationImage(
                                        image: MemoryImage(_cover!),
                                        fit: BoxFit.cover)
                                    : null),
                            child: _cover == null
                                ? Center(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                        Icon(Icons.add_photo_alternate_outlined,
                                            color: AppColors.textTertiary,
                                            size: 36),
                                        const SizedBox(height: 6),
                                        Text('Cover зураг',
                                            style: TextStyle(
                                                color: AppColors.textTertiary)),
                                      ]))
                                : null),
                      ),
                      const SizedBox(height: 16),
                      _field(_titleCtrl, 'Эвентийн нэр', maxLength: 120),
                      const SizedBox(height: 12),
                      _tile(Icons.location_on_outlined,
                          _venueName ?? 'Газар сонгох', _pickVenue),
                      const SizedBox(height: 12),
                      _tile(Icons.schedule, whenStr, _pickDateTime),
                      const SizedBox(height: 12),
                      _field(_priceCtrl, 'Газарт орох үнэ (₮) — 0 = үнэгүй',
                          number: true),
                      const SizedBox(height: 6),
                      Text(
                          'Зөвхөн мэдээлэл. Night Owl тасалбар худалдахгүй, төлбөр авахгүй.',
                          style: AppTextStyles.bodyXs
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      _field(_descCtrl, 'Тайлбар', lines: 3, maxLength: 5000),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: AppTextStyles.bodyXs
                                .copyWith(color: AppColors.error)),
                      ],
                      const SizedBox(height: 20),
                      if (_status != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_status!, style: AppTextStyles.bodySm)),
                      // Үндсэн үйлдэл — апп даяарх нэгдсэн gradient товч
                      GradientButton(
                        label: _pendingRow == null
                            ? 'Эвент нийтлэх'
                            : 'Дахин шалгах',
                        busy: _busy,
                        onPressed: _picking ? null : _save,
                      ),
                    ]),
        ));
  }

  Widget _field(TextEditingController c, String hint,
          {int lines = 1, bool number = false, int? maxLength}) =>
      TextField(
          controller: c,
          maxLines: lines,
          maxLength: maxLength,
          enabled: _canEdit,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.bgElevated,
              border: OutlineInputBorder(
                  borderRadius: AppRadii.mdR, borderSide: BorderSide.none)));

  Widget _tile(IconData i, String label, VoidCallback onTap) => _Tap(
      onTap: _canEdit ? onTap : null,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: AppRadii.mdR,
              border: Border.all(color: AppColors.hairline)),
          child: Row(children: [
            Icon(i, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.textPrimary))),
            Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
          ])));
}

// ─── Дарлт мэдрэмж — scale + hover курсор (веб) ───
class _Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Tap({required this.child, this.onTap});
  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor:
            widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown:
              widget.onTap == null ? null : (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            scale: _down ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

class _VenuePick extends StatefulWidget {
  final EventService service;
  final PublicationSession session;
  const _VenuePick({required this.service, required this.session});
  @override
  State<_VenuePick> createState() => _VenuePickState();
}

class _VenuePickState extends State<_VenuePick> {
  List<Map<String, dynamic>> _r = [];
  bool _loading = false;
  bool _failed = false; // алдааг хоосон жагсаалтаас ялгана
  Timer? _debounce;
  int _ticket = 0; // хожуу ирсэн хуучин хариу шинийг дарж бичихгүй
  String _lastQ = '';
  StreamSubscription<void>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.service.sessionChanges.listen((_) {
      if (!widget.session.isCurrent) _closeAfterSessionLoss();
    }, onError: (Object _) => _closeAfterSessionLoss());
    _run('');
  }

  void _closeAfterSessionLoss() {
    if (!mounted) return;
    _ticket++;
    _debounce?.cancel();
    setState(() {
      _r = [];
      _failed = true;
      _loading = false;
    });
    if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticket++;
    _debounce?.cancel();
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  // Товчлуур бүрт биш — 300ms завсарлагатай хайна
  void _search(String q) {
    _lastQ = q;
    _ticket++;
    setState(() {
      _loading = true;
      _failed = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    final my = ++_ticket;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.service.ownedVenues(widget.session, q);
      if (!mounted || my != _ticket) return;
      widget.session.check();
      _r = rows;
    } catch (_) {
      if (!mounted || my != _ticket) return;
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Газар сонгох', style: AppTextStyles.labelLg),
            const SizedBox(height: 12),
            TextField(
                autofocus: true,
                onChanged: _search,
                style:
                    AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                    hintText: 'Хайх...',
                    prefixIcon:
                        Icon(Icons.search, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.bgSurface,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: AppRadii.mdR,
                        borderSide: BorderSide.none))),
            const SizedBox(height: 8),
            SizedBox(
                height: (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        200)
                    .clamp(100.0, 320.0),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentStart, strokeWidth: 2))
                    : _failed
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Icon(Icons.wifi_off_outlined,
                                    color: AppColors.textTertiary, size: 36),
                                const SizedBox(height: 10),
                                Text('Алдаа гарлаа — дахин оролдоно уу',
                                    style: AppTextStyles.bodyMd.copyWith(
                                        color: AppColors.textSecondary)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                    onPressed: () => _run(_lastQ),
                                    child: const Text('Дахин оролдох')),
                              ]))
                        : _r.isEmpty
                            ? Center(
                                child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                        'Танд эзэмшдэг газар алга.\nЭхлээд "Газраа удирдах"-аас venue үүсгэнэ үү.',
                                        textAlign: TextAlign.center,
                                        style: AppTextStyles.bodyMd.copyWith(
                                            color: AppColors.textSecondary))))
                            : ListView.builder(
                                itemCount: _r.length,
                                itemBuilder: (_, i) => ListTile(
                                    leading: const Icon(Icons.location_on,
                                        color: AppColors.accentStart),
                                    mouseCursor: SystemMouseCursors.click,
                                    title: Text(_r[i]['name'] as String? ?? '',
                                        style: AppTextStyles.bodyMd.copyWith(
                                            color: AppColors.textPrimary)),
                                    onTap: () {
                                      if (widget.session.isCurrent) {
                                        Navigator.pop(context, _r[i]);
                                      } else {
                                        setState(() {
                                          _failed = true;
                                          _r = [];
                                        });
                                      }
                                    }))),
            const SizedBox(height: 12),
          ])));
}
