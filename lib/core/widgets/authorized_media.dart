import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart' as cached;
import '../../features/auth/providers/auth_provider.dart';
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

class _AuthorizedMediaState extends ConsumerState<AuthorizedMedia> {
  Future<String>? _url;
  String? _identity;
  @override
  Widget build(BuildContext context) {
    if (protectedStorageObject(widget.url) == null) {
      return widget.builder(widget.url);
    }
    final account = ref.watch(sessionUserIdProvider);
    final identity = '$account:${widget.url}';
    if (_identity != identity) {
      _identity = identity;
      _url = authorizedMediaUrl(widget.url);
    }
    return FutureBuilder<String>(
        key: ValueKey(identity),
        future: _url,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return widget.error?.call() ??
                const Center(child: Icon(Icons.lock_outline));
          }
          if (!snapshot.hasData) {
            return widget.placeholder?.call() ?? const SizedBox.shrink();
          }
          return widget.builder(snapshot.data!);
        });
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
  Widget build(BuildContext context) => AuthorizedMedia(
      url: imageUrl,
      placeholder: () =>
          placeholder?.call(context, imageUrl) ??
          SizedBox(width: width, height: height),
      error: () =>
          errorWidget?.call(
              context, imageUrl, StateError('Медиа үзэх боломжгүй')) ??
          const Icon(Icons.lock_outline),
      builder: (url) => cached.CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: memCacheWidth,
          fadeInDuration: fadeInDuration,
          placeholder: placeholder,
          errorWidget: errorWidget));
}
