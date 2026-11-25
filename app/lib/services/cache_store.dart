// Where the cache lives: real folders on phones/desktop, memory in the browser.
export 'cache_store_mem.dart' if (dart.library.io) 'cache_store_io.dart';
