import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/web_utils.dart';
import 'package:dentpal/utils/signup_state.dart';
import 'package:dentpal/firebase_action_handler_page.dart';
import 'package:dentpal/core/services/sub_account_service.dart';
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
  Future<void>? _subAccountFuture; // Cache the sub account resolution future
  String? _resolvedUid; // Track which UID we already resolved

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

  /// Resolve sub account session for a newly authenticated user.
  /// This must complete BEFORE showing HomePage.
  Future<void> _resolveSubAccountSession(String uid) async {
    // If the session manager already knows this is a sub-account, it was set
    // by the login page — no need to re-run the lookup.
    if (SubAccountSessionManager.isSubAccount) return;
    // If we already resolved for this uid, skip.
    if (_resolvedUid == uid) return;
    try {
      AppLogger.d('AuthWrapper: Resolving sub account status for $uid');
      final result = await SubAccountService.lookupSubAccount(uid);
      if (result != null) {
        SubAccountSessionManager.setSubAccountSession(
          subAccount: result.subAccount,
          parentUserId: result.parentUserId,
        );
        AppLogger.d(
          'AuthWrapper: Sub account detected: ${result.subAccount.email} '
          '(parent: ${result.parentUserId})',
        );
      } else {
        SubAccountSessionManager.setMainAccountSession();
        AppLogger.d('AuthWrapper: Main account confirmed: $uid');
      }
      _resolvedUid = uid;
    } catch (e) {
      AppLogger.d('AuthWrapper: Sub account lookup failed: $e');
      // Do NOT default to main account — that would grant unintended privileges
      // if the lookup fails for a real sub-account user.  Clear _resolvedUid so
      // the lookup is retried on the next auth event, and rethrow so the
      // FutureBuilder can surface an error state.
      _resolvedUid = null;
      rethrow;
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
        // During signup flow, return the cached screen to prevent any rebuilds
        if (SignupState.isInSignupFlow) {
          AppLogger.d('AuthWrapper: Auth state change ignored - user is in signup flow (event: ${snapshot.data?.uid ?? "signed-out"})');
          if (_cachedScreen == null) {
            _cachedScreen = const LoginPage();
          }
          return _cachedScreen!;
        }

        // Not logged in → show login page
        if (!snapshot.hasData || snapshot.data == null) {
          AppLogger.d('AuthWrapper: No user logged in, showing LoginPage');
          _cachedScreen = const LoginPage();
          _subAccountFuture = null;
          _resolvedUid = null;
          return _cachedScreen!;
        }

        // User IS logged in — but we must resolve sub account status first.
        // Use a FutureBuilder to wait for the sub account lookup to complete
        // before rendering HomePage. This prevents the race condition.
        final user = snapshot.data!;
        AppLogger.d('AuthWrapper: Auth state change - user: ${user.uid}');

        // Cache the future so it doesn't restart on every rebuild.
        // Do NOT set _resolvedUid here — _resolveSubAccountSession sets it
        // only after it successfully completes, so that a failed future leaves
        // _resolvedUid null and the retry path can kick off a fresh future.
        if (_resolvedUid != user.uid) {
          _subAccountFuture = _resolveSubAccountSession(user.uid);
        }

        return FutureBuilder<void>(
          future: _subAccountFuture,
          builder: (context, subAccountSnapshot) {
            if (subAccountSnapshot.connectionState != ConnectionState.done) {
              // Still resolving — show a loading indicator, NOT HomePage
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Lookup failed — fail closed: do not show HomePage.
            // Show an error screen with a retry button so the user is not
            // silently granted main-account access on a transient error.
            if (subAccountSnapshot.hasError) {
              AppLogger.d(
                'AuthWrapper: Sub account lookup error, showing retry screen: '
                '${subAccountSnapshot.error}',
              );
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Unable to verify your account type. '
                          'Please check your connection and try again.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            if (!mounted) return;
                            setState(() {
                              // Reset so _resolveSubAccountSession is re-triggered
                              // on the next build.
                              _resolvedUid = null;
                              _subAccountFuture = null;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Sub account status resolved — safe to show HomePage
            AppLogger.d('AuthWrapper: Sub account resolved, showing HomePage');
            _cachedScreen = const HomePage();
            return _cachedScreen!;
          },
        );
      },
    );
  }
}
