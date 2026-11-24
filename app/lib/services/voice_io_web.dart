import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// On the web the recorder ignores the path and returns a blob: URL.
Future<String> recordingPath(String ext) async => '';

Future<Uint8List> readRecording(String blobUrl) async => (await http.get(Uri.parse(blobUrl))).bodyBytes;
