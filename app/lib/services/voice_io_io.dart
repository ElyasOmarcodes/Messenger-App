import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> recordingPath(String ext) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/paigham-voice-${DateTime.now().millisecondsSinceEpoch}.$ext';
}

Future<Uint8List> readRecording(String path) async {
  final f = File(path);
  final bytes = await f.readAsBytes();
  try {
    await f.delete();
  } catch (_) {}
  return bytes;
}
