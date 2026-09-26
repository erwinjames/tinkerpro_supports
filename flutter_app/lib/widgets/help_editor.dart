import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/help_service.dart';
import 'help_html.dart';
import 'html_editor.dart';
import 'pick_source.dart';
import 'rich_html_editor.dart';

class HelpContentEditor extends StatefulWidget {
  const HelpContentEditor({
    super.key,
    required this.controller,
    required this.service,
    required this.colorPresets,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final HelpService service;
  final List<String> colorPresets;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  State<HelpContentEditor> createState() => _HelpContentEditorState();
}

class _HelpContentEditorState extends State<HelpContentEditor> {
  bool _busy = false;
  RichEditorHandle? _handle;

  void _insertBlock(String html) => _handle?.insertHtmlBlock(html);

  Future<void> _insertImage() async {
    final picked = await pickWithSource(
      context,
      allowedExtensions: kHelpImageExtensions,
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose an image file',
      imageMaxWidth: 1600,
      imageQuality: 82,
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;
    final extension = helpFileExtension(file.name);
    if (extension.isNotEmpty && !kHelpImageExtensions.contains(extension)) {
      _toast('Use a PNG, JPG, GIF or WEBP image.');
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await File(file.path).readAsBytes();
      if (bytes.length > kHelpInlineImageMaxBytes) {
        _toast(
          'That image is ${helpFormatBytes(bytes.length)}. '
          'Pick one under ${helpFormatBytes(kHelpInlineImageMaxBytes)}.',
        );
        return;
      }
      final size = await helpImageSize(bytes);
      final fitted = size == null
          ? null
          : helpFittedSize(size.width, size.height);
      final mime = helpImageMimeType(extension);
      final data = base64Encode(bytes);
      if (!mounted) return;
      _handle?.insertImage(
        'data:$mime;base64,$data',
        width: fitted?.width,
        height: fitted?.height,
      );
      _toast('Image added. Save the topic to upload it.');
    } catch (_) {
      _toast('Could not read that image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _insertVideo() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_rounded),
              title: const Text('Upload video file'),
              subtitle: Text(kHelpVideoExtensions.join(', ')),
              onTap: () => Navigator.of(ctx).pop('upload'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Video from link'),
              subtitle: const Text(
                'YouTube, Vimeo, Loom, Google Drive or a direct .mp4 link',
              ),
              onTap: () => Navigator.of(ctx).pop('link'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'link') {
      await _insertVideoLink();
      return;
    }
    await _uploadVideo();
  }

  Future<void> _insertVideoLink() async {
    final url = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video from link'),
        content: TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Video link',
            hintText: 'https://',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
    final raw = url.text.trim();
    url.dispose();
    if (saved != true || !mounted || raw.isEmpty) return;

    final embed = helpVideoEmbedUrl(raw);
    if (embed != null) {
      const width = kHelpMediaMaxWidth;
      final height = (width * 9 / 16).round();
      _insertBlock(
        '<p><iframe src="${helpEscapeHtml(embed)}" width="$width" '
        'height="$height" frameborder="0" allowfullscreen="allowfullscreen">'
        '</iframe></p>',
      );
      return;
    }
    if (kHelpVideoExtensions.contains(helpFileExtension(raw))) {
      _insertFileVideo(raw, '');
      return;
    }
    _toast(
      'That link is not a supported video. Use YouTube, Vimeo, Loom, '
      'Google Drive, Dailymotion, Streamable, or a direct .mp4/.webm link.',
    );
  }

  void _insertFileVideo(String url, String title) {
    const width = kHelpMediaMaxWidth;
    final height = (width * 9 / 16).round();
    final titleAttr = title.isEmpty ? '' : ' title="${helpEscapeHtml(title)}"';
    _insertBlock(
      '<p><video src="${helpEscapeHtml(url)}" width="$width" '
      'height="$height" controls="controls" preload="metadata"$titleAttr>'
      '</video></p>',
    );
  }

  Future<void> _uploadVideo() async {
    final picked = await pickWithSource(
      context,
      allowCamera: false,
      allowedExtensions: kHelpVideoExtensions,
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;

    final progress = ValueNotifier<double>(0);
    BuildContext? dialogContext;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          title: const Text('Uploading video'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (ctx, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: value),
                const SizedBox(height: 8),
                Text('${(value * 100).round()}%'),
              ],
            ),
          ),
        );
      },
    );

    setState(() => _busy = true);
    final result = await widget.service.uploadVideo(
      file.path,
      file.name,
      onProgress: (value) => progress.value = value,
    );
    final opened = dialogContext;
    if (opened != null && opened.mounted) Navigator.of(opened).pop();
    await dialog;
    progress.dispose();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.ok || result.url.isEmpty) {
      _toast(result.message ?? 'Video upload failed.');
      return;
    }
    _insertFileVideo(result.url, file.name);
    _toast('Video added. Remember to save the topic.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RichHtmlEditor(
      controller: widget.controller,
      colorPresets: widget.colorPresets,
      enabled: widget.enabled,
      busy: _busy,
      onChanged: widget.onChanged,
      hintText: 'Write the help document here…',
      footnote:
          'Tables and videos are kept exactly as they are. Switch to HTML '
          'if you need to edit them.',
      mediaHeaders: widget.service.mediaHeaders,
      extraTools: (handle, enabled) {
        _handle = handle;
        return [
          HtmlToolButton(
            icon: Icons.image_outlined,
            tooltip: 'Insert image',
            onPressed: enabled ? _insertImage : null,
          ),
          HtmlToolButton(
            icon: Icons.movie_outlined,
            tooltip: 'Insert video',
            onPressed: enabled ? _insertVideo : null,
          ),
        ];
      },
    );
  }
}
