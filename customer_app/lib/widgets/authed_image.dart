import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';

/// Tiny image widget that fetches bytes through the app's [ApiClient] (so
/// the persisted PHPSESSID cookie travels with the request). Replaces
/// `CachedNetworkImage` for chat attachments — the package uses its own
/// HTTP client by default, which means our cookie jar isn't applied and
/// the server returns 401 for `chat.downloadAttachment`.
///
/// Memory-only cache keyed by URL — fine for chat thumbnails since the
/// list is small and the user re-scrolling shouldn't refetch. If we ever
/// need disk persistence, swap in `flutter_cache_manager` with a custom
/// [HttpFileService] that goes through Dio.
class AuthedImage extends StatefulWidget {
  const AuthedImage({
    super.key,
    required this.api,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.maxWidth,
    this.maxHeight,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final ApiClient api;
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double? maxWidth;
  final double? maxHeight;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<AuthedImage> createState() => _AuthedImageState();
}

class _AuthedImageState extends State<AuthedImage> {
  static final Map<String, Uint8List> _cache = {};

  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AuthedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _future = _load();
    }
  }

  Future<Uint8List> _load() async {
    final cached = _cache[widget.url];
    if (cached != null) return cached;
    try {
      final res = await widget.api.dioGetBytes(widget.url);
      _cache[widget.url] = res;
      return res;
    } catch (e) {
      debugPrint('[authed-image] failed: ${widget.url} → $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = widget.placeholder ?? _defaultPlaceholder();
        } else if (snap.hasError || !snap.hasData) {
          child = widget.errorWidget ??
              const Icon(Icons.broken_image, color: Colors.white70);
        } else {
          child = Image.memory(
            snap.data!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            // Filter quality `medium` keeps thumbnails crisp without
            // chewing CPU on big originals.
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) =>
                widget.errorWidget ??
                const Icon(Icons.broken_image, color: Colors.white70),
          );
        }
        if (widget.maxWidth != null || widget.maxHeight != null) {
          child = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.maxWidth ?? double.infinity,
              maxHeight: widget.maxHeight ?? double.infinity,
            ),
            child: child,
          );
        }
        if (widget.borderRadius != null) {
          child = ClipRRect(
            borderRadius: widget.borderRadius!,
            child: child,
          );
        }
        return child;
      },
    );
  }

  Widget _defaultPlaceholder() {
    return SizedBox(
      width: widget.width ?? 220,
      height: widget.height ?? 140,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Helper extension on [ApiClient] — exposes a tiny "get raw bytes" since
/// the existing [ApiClient.get] only handles JSON.
extension ApiClientImageBytes on ApiClient {
  Future<Uint8List> dioGetBytes(String url) async {
    final res = await rawDio.get<List<int>>(
      url,
      options: dio.Options(
        responseType: dio.ResponseType.bytes,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final data = res.data;
    if (data == null) throw StateError('empty body');
    return Uint8List.fromList(data);
  }
}
