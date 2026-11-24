// Reads a finished recording into memory on any platform.
export 'voice_io_stub.dart' if (dart.library.io) 'voice_io_io.dart' if (dart.library.js_interop) 'voice_io_web.dart';
