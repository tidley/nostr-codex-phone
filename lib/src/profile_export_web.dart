import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> exportProfile(Uint8List bytes, String fileName) async {
  final url = html.Url.createObjectUrl(html.Blob(<Object>[bytes]));
  try {
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    return true;
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
