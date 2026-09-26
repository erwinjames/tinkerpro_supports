import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

typedef PickedFile = ({String path, String name});

Future<List<PickedFile>> pickWithSource(
  BuildContext context, {
  bool multiple = false,
  List<String>? allowedExtensions,
  String cameraLabel = 'Take a photo',
  String fileLabel = 'Choose from files',
  bool allowCamera = true,
  double? imageMaxWidth,
  int? imageQuality,
  void Function(String message)? onError,
}) async {
  final source = !allowCamera
      ? 'file'
      : await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: Text(cameraLabel),
                  onTap: () => Navigator.of(ctx).pop('camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.of(ctx).pop('gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: Text(fileLabel),
                  onTap: () => Navigator.of(ctx).pop('file'),
                ),
              ],
            ),
          ),
        );
  if (source == null) return const [];

  if (source == 'camera' || source == 'gallery') {
    final picker = ImagePicker();
    try {
      if (source == 'gallery' && multiple) {
        final shots = await picker.pickMultiImage(
          imageQuality: imageQuality,
          maxWidth: imageMaxWidth,
        );
        return [for (final s in shots) (path: s.path, name: s.name)];
      }
      final shot = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: imageQuality,
        maxWidth: imageMaxWidth,
      );
      if (shot == null) return const [];
      return [(path: shot.path, name: shot.name)];
    } catch (_) {
      onError?.call(
        source == 'camera'
            ? 'Could not open the camera.'
            : 'Could not open the gallery.',
      );
      return const [];
    }
  }

  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      allowMultiple: multiple,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
  } catch (_) {
    onError?.call('Could not open the file picker.');
    return const [];
  }
  return (result?.files ?? const <PlatformFile>[])
      .where((f) => f.path != null)
      .map((f) => (path: f.path!, name: f.name))
      .toList();
}
