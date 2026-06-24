class MediaUploadCancelledException implements Exception {
  const MediaUploadCancelledException({
    required this.server,
    required this.sessionId,
  });

  final String server;
  final int sessionId;

  @override
  String toString() =>
      'Media upload cancelled (session=$sessionId, server=$server)';
}

enum MediaSource { camera, photoPicker, filePicker }

class MediaSelection {
  const MediaSelection({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.contentType,
  });

  final String path;
  final String fileName;
  final String? extension;
  final String contentType;
}
