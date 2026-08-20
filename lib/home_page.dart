import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:dentpal/core/services/role_cache.dart';
import 'package:dentpal/core/services/sub_account_service.dart';
import 'package:dentpal/core/widgets/app_shell.dart';
import 'package:dentpal/product/pages/seller_dashboard_page.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:dentpal/profile/pages/csr_dashboard_page.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/signup_state.dart';

/// Picks which shell the signed-in account gets, and nothing else.
///
/// This used to be the app's navigation: it owned the bottom bar, the tab
/// index, the cart badge and the exit dialog, while the web side rail lived
/// separately inside the product listing page. All of that now belongs to
/// [AppShell], which outlives every page. What is left here is the one question
/// only this widget can answer — buyer, seller, or customer support.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final UserService _userService = UserService();

  /// Null until a role is known. Seeded synchronously from [RoleCache] when the
  /// account has been seen before, so the common case paints the right shell on
  /// the first frame rather than behind a spinner.
  UserRole? _role;

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _seedRoleFromCache();

    if (!SignupState.isInSignupFlow) {
      _resolveRole();
    } else {
      AppLogger.d('HomePage: skipping role resolution during signup flow');
      _role ??= UserRole.buyer;
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Auth churns during signup (reCAPTCHA, verification) and re-resolving
      // mid-flow would swap the shell out from under SignupFlow.
      if (SignupState.isInSignupFlow) {
        AppLogger.d('HomePage: auth change ignored during signup flow');
        return;
      }
      _resolveRole();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _seedRoleFromCache() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _role = UserRole.buyer;
      return;
    }

    _role = RoleCache.peek(user.uid);
    if (_role != null) return;

    // Not in memory — read it off disk and adopt it only if the live lookup
    // has not already answered.
    RoleCache.load(user.uid).then((cached) {
      if (mounted && cached != null && _role == null) {
        setState(() => _role = cached);
      }
    });
  }

  void _setRole(UserRole role) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) RoleCache.save(user.uid, role);
    if (mounted && _role != role) setState(() => _role = role);
  }

  Future<void> _resolveRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _role = UserRole.buyer);
        return;
      }

      // Detect sub account if not already identified. This handles the case
      // where AuthWrapper navigates directly to HomePage (e.g. on app restart
      // with a persisted sub account session). Skip entirely when AuthWrapper
      // (or the login page) has already resolved the role for this UID —
      // re-running the lookup is redundant and, if it fails transiently, would
      // trigger an unintended sign-out.
      if (SubAccountSessionManager.resolvedForUid != user.uid) {
        try {
          final result = await SubAccountService.lookupSubAccount(user.uid);
          if (result != null) {
            SubAccountSessionManager.setSubAccountSession(
              subAccount: result.subAccount,
              parentUserId: result.parentUserId,
            );
            AppLogger.d(
              'HomePage: detected sub account: ${result.subAccount.email} '
              '(parent: ${result.parentUserId})',
            );
          } else {
            SubAccountSessionManager.setMainAccountSession();
          }
        } catch (e) {
          AppLogger.d('HomePage: sub account lookup failed: $e');
          // Do NOT default to main account — fail closed so a sub-account user
          // whose lookup fails transiently does not get unintended
          // main-account access. Sign out and let AuthWrapper handle
          // re-resolution on the next login.
          if (mounted) {
            await FirebaseAuth.instance.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to verify your account type. '
                  'Please check your connection and sign in again.',
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      } else {
        AppLogger.d(
          'HomePage: role already resolved by AuthWrapper for ${user.uid}',
        );
      }

      if (await _userService.isCurrentUserCustomerSupport(forceRefresh: true)) {
        _setRole(UserRole.customerSupport);
        return;
      }

      final isSeller = await _userService.isCurrentUserSeller(
        forceRefresh: true,
      );
      _setRole(isSeller ? UserRole.seller : UserRole.buyer);
    } catch (e) {
      AppLogger.d('HomePage: error resolving role: $e');
      // Fall back to the buyer shell rather than leaving the app blank.
      if (mounted && _role == null) setState(() => _role = UserRole.buyer);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_role) {
      case UserRole.customerSupport:
        // CSR and seller shells own their own internal navigation. They only
        // install their own exit-confirmation PopScope when `isStandalone`,
        // which also makes them draw a back arrow — wrong for a root shell —
        // so the exit scope stays here, as it was before AppShell existed.
        return _withExitConfirmation(const CsrDashboardPage());
      case UserRole.seller:
        return _withExitConfirmation(const SellerDashboardPage());
      case UserRole.buyer:
        // AppShell installs its own PopScope: back leaves a tab for Home first,
        // and only then offers to exit.
        return const AppShell();
      case null:
        // First sight of this account on this device. Brief, and only until the
        // two role reads land.
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }

  Widget _withExitConfirmation(Widget child) {
    return PopScope(
      // On web the browser owns navigation; on mobile, confirm before exiting.
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || kIsWeb) return;
        if (await showAppExitConfirmation(context)) SystemNavigator.pop();
      },
      child: child,
    );
  }
}
