// Cross-platform utilities for web and mobile
import 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart'
    if (dart.library.io) 'web_utils_mobile.dart';

String getCurrentPath() => getCurrentPathImpl();

void updateUrl(String path) => updateUrlImpl(path);
