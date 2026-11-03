import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart' as cached;
import '../../features/auth/providers/auth_provider.dart';
import '../../features/discovery/services/discovery_service.dart';
import '../services/media_access.dart';

class AuthorizedMedia extends ConsumerStatefulWidget {
  final String url;
  final Widget Function(String) builder;
  final Widget Function()? placeholder, error;
  const AuthorizedMedia(
      {super.key,
      required this.url,
      required this.builder,
      this.placeholder,
      this.error});
  @override
  ConsumerState<AuthorizedMedia> createState() => _AuthorizedMediaState();
}

class _AuthorizedMediaState extends ConsumerState<AuthorizedMedia>
    with WidgetsBindingObserver {
  static const _lifetime = Duration(minutes: 5);
  static const _refreshEarly = Duration(seconds: 30);
  static const _requestDeadline = Duration(seconds: 12);
  Timer? _refreshTimer, _deadlineTimer;
  String? _identity, _owner, _source;
  int? _social;
  int _request = 0;
  int? _pending;
  DateTime? _expiresAt, _nextAttempt;
  Object? _error;
  bool _foreground = true, _onstage = true, _retryAvailable = true;
  Future<String> Function(String)? _signer;
  DateTime get _now => ref.read(authorizedMediaClockProvider)();
  bool get _active => _foreground && _onstage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onstage = TickerMode.valuesOf(context).enabled;
    if (_onstage == onstage) return;
    _onstage = onstage;
    if (_active) {
      _resume();
    } else {
      _suspend();
    }
  }

  @override
  void didUpdateWidget(covariant AuthorizedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        _expiresAt != null &&
        !_expiresAt!.isAfter(_now) &&
        (_nextAttempt == null || !_nextAttempt!.isAfter(_now))) {
      _resume();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_active) {
      _nextAttempt = null;
      _retryAvailable = true;
      _resume();
    } else {
      _suspend();
    }
  }

  void _suspend() {
    _refreshTimer?.cancel();
    _deadlineTimer?.cancel();
    _refreshTimer = _deadlineTimer = null;
    _pending = null;
    _request++;
  }

  void _resume() {
    if (!_active || _identity == null || _signer == null) return;
    if (_source == null ||
        _error != null ||
        _expiresAt == null ||
        !_expiresAt!.isAfter(_now)) {
      _sign();
    } else {
      _scheduleRefresh();
    }
  }

  bool _current(int request, String identity) =>
      mounted &&
      _pending == request &&
      _identity == identity &&
      ref.read(sessionUserIdProvider) == _owner &&
      ref.read(socialVersionProvider) == _social;

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!_active || _expiresAt == null) return;
    final delay = _expiresAt!.subtract(_refreshEarly).difference(_now);
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, _sign);
  }

  void _sign({bool notify = true}) {
    if (!_active || _pending != null || _identity == null || _signer == null) {
      return;
    }
    _refreshTimer?.cancel();
    final request = ++_request;
    final identity = _identity!;
    final issuedAt = _now;
    _pending = request;
    if (_source == null) _error = null;
    if (notify && mounted) setState(() {});
    void failed(Object error) {
      if (!_current(request, identity)) return;
      _deadlineTimer?.cancel();
      _pending = null;
      _error = error;
      _nextAttempt = _now.add(const Duration(seconds: 30));
      // Keep already loaded media during a transient renewal failure. A single
      // bounded retry avoids turning an offline grid into a polling loop.
      if (_active && _retryAvailable) {
        _retryAvailable = false;
        _refreshTimer = Timer(const Duration(seconds: 30), _sign);
      }
      setState(() {});
    }

    _deadlineTimer = Timer(_requestDeadline,
        () => failed(TimeoutException('Media signing timed out')));
    Future<String>.sync(() => _signer!(widget.url)).then((source) {
      if (!_current(request, identity)) return;
      _deadlineTimer?.cancel();
      _pending = null;
      _source = source;
      _error = null;
      _nextAttempt = null;
      _retryAvailable = true;
      _expiresAt = issuedAt.add(_lifetime);
      _scheduleRefresh();
      setState(() {});
    }, onError: (Object error, StackTrace _) => failed(error));
  }

  @override
  Widget build(BuildContext context) {
    if (protectedStorageObject(widget.url) == null) {
      if (_identity != null) {
        _suspend();
        _identity = null;
        _source = null;
      }
      return widget.builder(widget.url);
    }
    final account = ref.watch(sessionUserIdProvider);
    final accessVersion = ref.watch(socialVersionProvider);
    final signer = ref.watch(authorizedMediaSignerProvider);
    final identity = '$account:$accessVersion:${widget.url}';
    if (_identity != identity || _signer != signer) {
      _suspend();
      _identity = identity;
      _owner = account;
      _social = accessVersion;
      _signer = signer;
      _source = null;
      _error = null;
      _expiresAt = _nextAttempt = null;
      _retryAvailable = true;
      _sign(notify: false);
    }
    if (_source != null) return widget.builder(_source!);
    if (_error != null) {
      return widget.error?.call() ??
          IconButton(
              tooltip: 'Медиа дахин ачаалах',
              onPressed: () {
                _retryAvailable = true;
                _sign();
              },
              icon: const Icon(Icons.refresh));
    }
    return widget.placeholder?.call() ?? const SizedBox.shrink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suspend();
    super.dispose();
  }
}

class AuthorizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width, height;
  final BoxFit? fit;
  final int? memCacheWidth;
  final Duration fadeInDuration;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  const AuthorizedImage(
      {super.key,
      required this.imageUrl,
      this.width,
      this.height,
      this.fit,
      this.memCacheWidth,
      this.fadeInDuration = const Duration(milliseconds: 150),
      this.placeholder,
      this.errorWidget});
  @override
  Widget build(BuildContext context) {
    Widget image(String url) => cached.CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        fadeInDuration: fadeInDuration,
        placeholder: placeholder,
        errorWidget: errorWidget);
    if (protectedStorageObject(imageUrl) == null) return image(imageUrl);
    return AuthorizedMedia(
        url: imageUrl,
        placeholder: () =>
            placeholder?.call(context, imageUrl) ??
            SizedBox(width: width, height: height),
        error: () =>
            errorWidget?.call(
                context, imageUrl, StateError('Медиа үзэх боломжгүй')) ??
            const Icon(Icons.lock_outline),
        builder: image);
  }
}
