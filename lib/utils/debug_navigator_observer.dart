import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';

/// Debug navigator observer that logs all route changes.
/// This helps diagnose unexpected navigation during signup flow.
class DebugNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLogger.d('NAV_OBSERVER: PUSHED ${_routeName(route)} (previous: ${_routeName(previousRoute)})');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLogger.d('NAV_OBSERVER: POPPED ${_routeName(route)} (back to: ${_routeName(previousRoute)})');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLogger.d('NAV_OBSERVER: REMOVED ${_routeName(route)} (previous: ${_routeName(previousRoute)})');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLogger.d('NAV_OBSERVER: REPLACED ${_routeName(oldRoute)} with ${_routeName(newRoute)}');
  }

  String _routeName(Route<dynamic>? route) {
    if (route == null) return 'null';
    return route.settings.name ?? route.runtimeType.toString();
  }
}
