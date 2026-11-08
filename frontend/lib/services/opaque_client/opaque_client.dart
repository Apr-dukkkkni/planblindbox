export 'opaque_client_stub.dart'
    if (dart.library.io) 'opaque_client_native.dart'
    if (dart.library.js_interop) 'opaque_client_web.dart';
