import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> exportProfile(Uint8List bytes, String fileName) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export profile',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: bytes,
  );
  return path != null;
}
