import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/web_utils.dart';
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
        // If the snapshot has user data, then they're already authenticated
        if (snapshot.hasData && snapshot.data != null) {
          return const HomePage();
        }
        // Otherwise, they're not signed in
        return const LoginPage();
      },
    );
  }
}
