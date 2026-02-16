import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/web_utils.dart';
import 'package:dentpal/utils/signup_state.dart';
import 'package:dentpal/firebase_action_handler_page.dart';
import 'login_page.dart';
import 'home_page.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isCheckingFirebaseAction = true;
  bool _hasFirebaseAction = false;
  Widget? _cachedScreen; // Cache the screen before signup starts

  @override
  void initState() {
    super.initState();

    // Check for Firebase action query parameters on web FIRST
    if (kIsWeb) {
      _checkForFirebaseAction();
    } else {
      // Not on web, no need to check
      _isCheckingFirebaseAction = false;
    }
  }

  /// Check if the URL contains Firebase action query parameters
  /// and navigate to the handler page if found
  void _checkForFirebaseAction() {
    if (!kIsWeb || !mounted) return;

    try {
      // Parse query parameters from URL
      final queryParams = getUrlQueryParameters();

      final mode = queryParams['mode'];
      final oobCode = queryParams['oobCode'];

      AppLogger.d(
        'Checking for Firebase action - mode: $mode, oobCode present: ${oobCode != null}',
      );

      // If Firebase action parameters are present, navigate to handler
      if (mode != null && oobCode != null) {
        AppLogger.d('Firebase action detected in AuthWrapper: mode=$mode');
        setState(() {
          _hasFirebaseAction = true;
          _isCheckingFirebaseAction = false;
        });

        // Navigate immediately
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => FirebaseActionHandlerPage(
                mode: mode,
                oobCode: oobCode,
                apiKey: queryParams['apiKey'],
                continueUrl: queryParams['continueUrl'],
              ),
            ),
          );
        });
      } else {
        AppLogger.d('No Firebase action parameters found in URL');
        setState(() {
          _isCheckingFirebaseAction = false;
        });
      }
    } catch (e) {
      AppLogger.d('Error checking for Firebase action: $e');
      setState(() {
        _isCheckingFirebaseAction = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we're still checking for Firebase actions, show loading
    if (_isCheckingFirebaseAction) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If we found a Firebase action, don't show anything (will navigate away)
    if (_hasFirebaseAction) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Otherwise, show normal auth flow
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Determine what screen should be shown based on auth state
        Widget screenToShow;
        
        if (snapshot.hasData && snapshot.data != null) {
          screenToShow = const HomePage();
        } else {
          screenToShow = const LoginPage();
        }
        
        // During signup flow, return the cached screen to prevent any rebuilds
        if (SignupState.isInSignupFlow) {
          AppLogger.d('AuthWrapper: Auth state change ignored - user is in signup flow (event: ${snapshot.data?.uid ?? "signed-out"})');
          // Cache and return the screen (or return the previously cached one)
          if (_cachedScreen == null) {
            _cachedScreen = screenToShow;
          }
          return _cachedScreen!;
        }
        
        // Log auth state changes for debugging
        AppLogger.d('AuthWrapper: Auth state change - user: ${snapshot.data?.uid ?? "null"}, showing: ${screenToShow.runtimeType}');
        
        // Not in signup, cache the current screen and return it
        _cachedScreen = screenToShow;
        return screenToShow;
      },
    );
  }
}
