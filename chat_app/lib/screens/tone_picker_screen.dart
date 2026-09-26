import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/ringtone_service.dart';
import '../services/tone_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class TonePickerScreen extends StatefulWidget {
  const TonePickerScreen({
    super.key,
    required this.slot,
    required this.current,
  });

  final ToneSlot slot;
  final ToneChoice current;

  @override
  State<TonePickerScreen> createState() => _TonePickerScreenState();
}

class _TonePickerScreenState extends State<TonePickerScreen> {
  late ToneChoice _selected = widget.current;
  List<DeviceSound> _device = const [];
  bool _loadingDevice = true;
  bool _importing = false;

  bool get _isCall => widget.slot == ToneSlot.call;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  @override
  void dispose() {
    TonePrefs.stopPreview();
    super.dispose();
  }

  Future<void> _loadDevice() async {
    final sounds = await TonePrefs.deviceSounds(widget.slot);
    if (!mounted) return;
    setState(() {
      _device = sounds;
      _loadingDevice = false;
    });
  }

  Future<void> _choose(ToneChoice choice) async {
    setState(() => _selected = choice);
    await TonePrefs.preview(choice, loop: false);
  }

  Future<void> _pickFile() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final uri = await TonePrefs.importFile(widget.slot, path);
      if (!mounted) return;
      if (uri.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('COULD NOT USE THAT FILE')),
        );
        return;
      }
      await _choose(ToneChoice(
        kind: ToneKind.custom,
        value: uri,
        label: result?.files.single.name ?? 'Custom sound',
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  bool _isSelected(ToneChoice choice) {
    if (choice.kind != _selected.kind) return false;
    if (choice.kind == ToneKind.preset || choice.isUri) {
      return choice.value == _selected.value;
    }
    return true;
  }

  Widget _row(ToneChoice choice, {IconData? icon, String? subtitle}) {
    final selected = _isSelected(choice);
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => _choose(choice),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Brand.signal : context.brand.paperDim,
              size: 20,
            ),
            const SizedBox(width: 12),
            if (icon != null) ...[
              Icon(icon, size: 18, color: context.brand.paperDim),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  if (subtitle != null)
                    Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            if (!choice.isWeb && !choice.isSilent)
              IconButton(
                tooltip: 'Preview',
                icon: const Icon(Icons.play_arrow, size: 20),
                color: context.brand.paperDim,
                onPressed: () => TonePrefs.preview(choice, loop: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      title: _isCall ? 'Call ringtone' : 'Message tone',
      onBack: () {
        TonePrefs.stopPreview();
        Navigator.of(context).pop(_selected);
      },
      showBottomBrand: false,
      child: ListView(
        children: [
          _row(
            ToneChoice.web,
            icon: Icons.cloud_outlined,
            subtitle: 'Follow the sound picked in the web app',
          ),
          _row(ToneChoice.silent, icon: Icons.notifications_off_outlined),
          InkWell(
            onTap: _importing ? null : _pickFile,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Icon(Icons.library_music_outlined,
                      size: 18, color: context.brand.paperDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _importing ? 'Adding…' : 'Choose an audio file…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 20, color: context.brand.paperDim),
                ],
              ),
            ),
          ),
          if (_selected.kind == ToneKind.custom)
            _row(_selected, icon: Icons.audiotrack_outlined),
          _heading('App tones'),
          ...kSoundPresets.keys.map(
            (name) => _row(
              ToneChoice(
                kind: ToneKind.preset,
                value: name,
                label: _presetLabel(name),
              ),
              icon: Icons.graphic_eq,
            ),
          ),
          _heading(_isCall ? 'Phone ringtones' : 'Phone notification sounds'),
          if (_loadingDevice)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_device.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No sounds found on this phone.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ..._device.map(
              (sound) => _row(
                ToneChoice(
                  kind: ToneKind.device,
                  value: sound.uri,
                  label: sound.title,
                ),
                icon: Icons.phone_android,
              ),
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _presetLabel(String name) =>
      name[0].toUpperCase() + name.substring(1);
}
