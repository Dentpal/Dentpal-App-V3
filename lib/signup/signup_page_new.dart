import 'package:flutter/material.dart';
import 'signup_new_step1_idverification.dart';
import 'signup_new_step2_personal_details.dart';
import 'signup_new_step3_acc_credentials.dart';
import 'signup_controller.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/signup_state.dart';

class SignUpPageNew extends StatefulWidget {
  const SignUpPageNew({super.key});

  @override
  State<SignUpPageNew> createState() => _SignUpPageNewState();
}

class _SignUpPageNewState extends State<SignUpPageNew> with WidgetsBindingObserver {
  final SignupController _controller = SignupController();
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    // Set flag to prevent auth state changes from triggering navigation
    SignupState.isInSignupFlow = true;
    AppLogger.d('SignUpPageNew initiated, set isInSignupFlow = true');
    // Listen for app lifecycle changes (e.g. returning from reCAPTCHA browser)
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    AppLogger.d('SignUpPageNew lifecycle state changed to: $state');
    if (state == AppLifecycleState.resumed) {
      // App returned to foreground (e.g. after reCAPTCHA)
      // Re-assert signup flag to prevent any navigation
      SignupState.isInSignupFlow = true;
      AppLogger.d('App resumed during signup flow - re-asserted isInSignupFlow = true');

      // Verify SignUpPageNew is still the active route after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          AppLogger.d('SignUpPageNew still mounted 500ms after resume - current page: $_currentPage');
          final route = ModalRoute.of(context);
          if (route != null) {
            AppLogger.d('SignUpPageNew route isCurrent: ${route.isCurrent}, isActive: ${route.isActive}');
            if (!route.isCurrent && route.isActive) {
              AppLogger.d('WARNING: SignUpPageNew is no longer the top route!');
            }
          }
        } else {
          AppLogger.d('WARNING: SignUpPageNew NOT mounted 500ms after resume - route was destroyed!');
        }
      });

      // Also check at 1.5s for any delayed navigation that might have been triggered
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          AppLogger.d('SignUpPageNew still mounted 1500ms after resume - current page: $_currentPage');
          final route = ModalRoute.of(context);
          if (route != null && !route.isCurrent) {
            AppLogger.d('WARNING: SignUpPageNew lost top-route status 1500ms after resume!');
          }
        } else {
          AppLogger.d('CRITICAL: SignUpPageNew NOT mounted 1500ms after resume!');
        }
      });
    } else if (state == AppLifecycleState.paused) {
      AppLogger.d('SignUpPageNew: App paused (e.g. going to Safari for reCAPTCHA)');
    } else if (state == AppLifecycleState.inactive) {
      AppLogger.d('SignUpPageNew: App inactive');
    } else if (state == AppLifecycleState.detached) {
      AppLogger.d('SignUpPageNew: App detached - may be terminated!');
    }
  }

  void nextPage() {
    AppLogger.d('SignUpPageNew nextPage called - current: $_currentPage');
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _currentPage++;
        AppLogger.d('SignUpPageNew moved to page: $_currentPage');
      });
    }
  }

  void previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _currentPage--;
      });
    }
  }

  @override
  void deactivate() {
    AppLogger.d('SignUpPageNew DEACTIVATED - route is being removed from the tree');
    super.deactivate();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Clear the flag when leaving signup
    SignupState.isInSignupFlow = false;
    AppLogger.d('SignUpPageNew DISPOSED, set isInSignupFlow = false');
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent accidental back navigation during signup (especially during phone verification)
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Only allow going back on the first step
        if (_currentPage == 0) {
          SignupState.isInSignupFlow = false;
          AppLogger.d('SignUpPageNew: User exited signup from first step');
          Navigator.of(context).pop();
        } else {
          // Go to previous step instead of popping the entire signup flow
          AppLogger.d('SignUpPageNew: Back pressed on step $_currentPage - going to previous step');
          previousPage();
        }
      },
      child: AuthScaffold(
        header: AuthHeader(
          title: _stepTitle,
          subtitle: 'Step ${_currentPage + 1} of $_stepCount — $_stepBlurb',
          // The arrow is always present: on the first step it leaves signup,
          // on the others it walks back through the PageView. Wiring it here
          // rather than letting the header pop the route keeps both meanings in
          // one place, next to the PopScope that already handles the hardware
          // back button.
          showBack: true,
          onBack: _handleBack,
          bottom: AuthStepBar(total: _stepCount, current: _currentPage),
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            AppLogger.d('SignUpPageNew page changed to: $index');
            setState(() {
              _currentPage = index;
            });
          },
          children: [
            SignupNewStep1IdVerification(
              controller: _controller,
              onNext: nextPage,
            ),
            SignupNewStep2PersonalDetails(
              controller: _controller,
              onNext: nextPage,
              onBack: previousPage,
            ),
            SignupNewStep3AccCredentials(
              controller: _controller,
              onBack: previousPage,
            ),
          ],
        ),
      ),
    );
  }

  void _handleBack() {
    if (_currentPage == 0) {
      SignupState.isInSignupFlow = false;
      AppLogger.d('SignUpPageNew: User exited signup from first step');
      Navigator.of(context).pop();
    } else {
      previousPage();
    }
  }

  static const int _stepCount = 3;

  String get _stepTitle => switch (_currentPage) {
    0 => 'Verify your ID',
    1 => 'Your details',
    2 => 'Create your account',
    _ => 'Verify your ID',
  };

  /// The half-sentence that follows "Step n of 3 —" in the header.
  String get _stepBlurb => switch (_currentPage) {
    0 => 'scan your PRC ID',
    1 => 'tell us who you are',
    2 => 'set your email and password',
    _ => 'scan your PRC ID',
  };
}
