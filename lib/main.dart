import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/product/products_module.dart';
import 'package:dentpal/product/checkout_routes.dart';
import 'package:dentpal/product/pages/edit_product_page.dart';
import 'package:dentpal/product/pages/store_page.dart';
import 'package:dentpal/profile/pages/seller_listings_page.dart';
import 'package:dentpal/profile/pages/settings/settings_page.dart';
import 'package:dentpal/profile/pages/chats_page.dart';
import 'package:dentpal/profile/pages/chat_detail_page.dart';
import 'package:dentpal/profile/pages/shipping_addresses_page.dart';
import 'package:dentpal/profile/pages/reward_points_page.dart';
import 'package:dentpal/profile/pages/settings/manage_sub_accounts_page.dart';
import 'package:dentpal/profile/pages/settings/change_mobile_page.dart';
import 'package:dentpal/profile/pages/settings/change_password_page.dart';
import 'package:dentpal/profile/pages/settings/edit_profile_page.dart';
import 'package:dentpal/core/models/sub_account_model.dart';
import 'package:dentpal/profile/models/shipping_address.dart';
import 'package:dentpal/auth_wrapper.dart';
import 'package:dentpal/home_page.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/core/app_theme/app_theme.dart';
import 'package:dentpal/core/app_theme/theme_controller.dart';
import 'package:dentpal/core/widgets/app_shell.dart';
import 'package:dentpal/core/services/session_cache.dart';
import 'package:dentpal/services/deep_link_service.dart';
import 'package:dentpal/services/notification_service.dart';
import 'package:dentpal/services/in_app_notification_widget.dart';
import 'package:dentpal/reset_password_page.dart';
import 'package:dentpal/change_password_standalone_page.dart';
import 'package:dentpal/firebase_action_handler_page.dart';
import 'package:dentpal/public_privacy_policy_page.dart';
import 'package:dentpal/public_terms_of_service_page.dart';
import 'package:dentpal/public_support_page.dart';
import 'firebase_options.dart';
import 'package:dentpal/utils/web_utils.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/signup_state.dart';
import 'package:dentpal/utils/debug_navigator_observer.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path-based URL strategy for clean URLs without hash (#)
  // This enables URLs like /privacy-policy instead of /#/privacy-policy
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // Check if Firebase is already initialized
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      // Firebase is already initialized, which is fine
      AppLogger.d('Firebase already initialized');
    } else {
      // Re-throw other errors
      rethrow;
    }
  }

  // Set Firestore cache size to 100MB
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
  );

  // Watch for account changes and drop every per-account cached read.
  SessionCache.start();

  // Initialize notification service (only for mobile platforms)
  if (!kIsWeb) {
    print('=== MAIN.DART: Initializing notification service for MOBILE ===');
    AppLogger.i('Initializing notification service for mobile...');
    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service
    print('=== Calling NotificationService().initialize()...');
    await NotificationService().initialize();
    print('=== NotificationService().initialize() completed!');
    AppLogger.i('Notification service initialized');
  } else {
    print('=== MAIN.DART: Skipping notification service (WEB) ===');
    AppLogger.i('Skipping notification service (running on web)');
  }

  // Restore the saved appearance before the first frame, so the app never
  // flashes the wrong one on launch.
  await ThemeController.instance.load();

  runApp(const MyApp());
}

/// Query parameters the app was launched with, captured before the address bar
/// is rewritten. Empty off the web, and empty when the launch URL carried none.
///
/// Only the payment redirect needs these: it is the one entry point that hands
/// the app data in a query string rather than in a route argument.
Map<String, String> _launchQueryParameters = const {};

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global navigator key for deep link navigation AND notification navigation
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // The whole app is rebuilt when the appearance changes, so both the
    // Material theme and every InkPalette surface flip together.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) => _buildApp(context, themeMode),
    );
  }

  Widget _buildApp(BuildContext context, ThemeMode themeMode) {
    // Set the navigator key in NotificationService for push notification navigation
    NotificationService.setNavigatorKey(navigatorKey);

    // Initialize deep link service
    DeepLinkService.initialize(navigatorKey);

    final materialApp = MaterialApp(
      title: 'DentPal',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      navigatorKey: navigatorKey,
      navigatorObservers: [DebugNavigatorObserver(), ShellUrlObserver()],
      initialRoute: _getInitialRoute(),
      routes: {
        '/': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/auth': (context) => const AuthWrapper(),
        '/home': (context) => const HomePage(),
        // The two endings of checkout are built in `onGenerateRoute` instead,
        // so they can be handed the ids the payment redirect carries.
        '/products': (context) => const ProductListingPage(),
        '/cart': (context) => const CartPage(),
        '/add-product': (context) => const AddProductPage(),
        '/seller-listings': (context) => const SellerListingsPage(),
        '/profile/settings': (context) => const SettingsPage(),
        '/profile/chats': (context) => const ChatsPage(),
        '/profile/address': (context) => const ShippingAddressesPage(),
        '/profile/sub-accounts': (context) => const ManageSubAccountsPage(),
        '/profile/settings/change-phone-number': (context) =>
            const ChangeMobilePage(),
        '/profile/settings/change-password': (context) =>
            const ChangePasswordPage(),
        '/profile/settings/edit-profile': (context) => const EditProfilePage(),
        '/privacy-policy': (context) => const PublicPrivacyPolicyPage(),
        '/terms-of-service': (context) => const PublicTermsOfServicePage(),
        '/support': (context) => const PublicSupportPage(),
        // The address this page shipped at, and the one currently registered
        // as the Play Store listing's support URL. Kept pointing at the same
        // page so links already out in the world keep resolving.
        '/support-url': (context) => const PublicSupportPage(),
      },
      onGenerateRoute: (settings) {
        // The two endings of checkout, plus the legacy spellings of them.
        //
        // `/payment-success` and `/payment-failed` stay reachable because they
        // are the redirect targets already configured with PayMongo: a payment
        // session created before this change still comes back to them, and so
        // does one created by an older build still in someone's browser.
        final outcomeRoute = _checkoutOutcomeRoute(settings);
        if (outcomeRoute != null) return outcomeRoute;

        // Handle Firebase action links (email verification, password reset, email recovery)
        // These come with query parameters: mode, oobCode, apiKey, continueUrl
        if (settings.name == '/' && settings.arguments != null) {
          final args = settings.arguments as Map<String, dynamic>?;
          final mode = args?['mode'] as String?;
          final oobCode = args?['oobCode'] as String?;

          if (mode != null && oobCode != null) {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => FirebaseActionHandlerPage(
                mode: mode,
                oobCode: oobCode,
                apiKey: args?['apiKey'] as String?,
                continueUrl: args?['continueUrl'] as String?,
              ),
            );
          }
        }

        // One conversation: /profile/chats/<chatRoomId>.
        //
        // In-app pushes hand the counterparty over in `arguments` so the header
        // is right on the first frame; a pasted or reloaded link has none, and
        // ChatDetailPage reads them off the room instead.
        const chatPrefix = '/profile/chats/';
        if (settings.name?.startsWith(chatPrefix) ?? false) {
          final chatRoomId = settings.name!.substring(chatPrefix.length);
          if (chatRoomId.isNotEmpty) {
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => ChatDetailPage(
                chatRoomId: chatRoomId,
                otherUserId: args?['otherUserId'] as String?,
                otherUserName: args?['otherUserName'] as String?,
                otherUserShopName: args?['otherUserShopName'] as String?,
              ),
            );
          }
        }

        // The address editor. Adding needs nothing; editing needs to know which
        // address, and the path deliberately does not say — so it travels in
        // `arguments`.
        if (settings.name == '/profile/address/add') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const AddEditAddressPage(),
          );
        }
        if (settings.name == '/profile/address/edit') {
          final address = settings.arguments as ShippingAddress?;
          // Null means the URL was opened cold rather than pushed from a card,
          // so there is no address to edit. Returning null drops just this
          // segment and leaves the buyer on the list underneath it.
          if (address == null) return null;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => AddEditAddressPage(address: address),
          );
        }

        // Reward points. A push from Profile hands the buyer's document over
        // in `arguments` so the balance is right on the first frame; a pasted
        // or reloaded link has none, and the page reads it itself.
        if (settings.name == '/profile/rewards') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => RewardPointsPage(userData: args),
          );
        }

        // The assistant editor, same shape as the address one: adding needs
        // nothing, editing needs to know which assistant, and the path
        // deliberately does not say — so it travels in `arguments`.
        if (settings.name == '/profile/sub-accounts/add') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const SubAccountEditorPage(),
          );
        }
        if (settings.name == '/profile/sub-accounts/edit') {
          final subAccount = settings.arguments as SubAccount?;
          // Null means the URL was opened cold rather than pushed from a card,
          // so there is nobody to edit. Returning null drops just this segment
          // and leaves the buyer on the list underneath it.
          if (subAccount == null) return null;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => SubAccountEditorPage(subAccount: subAccount),
          );
        }

        // '/profile' itself is a shell tab, not a route — it only turns up here
        // as an intermediate segment while Navigator builds the stack for a
        // deep link like '/profile/chats/<id>'. Null skips it; falling through
        // to the AuthWrapper default would wedge a stray page mid-stack.
        if (settings.name == '/profile') return null;

        // Handle dynamic product routes
        if (settings.name?.startsWith('/product/') ?? false) {
          final productId = settings.name!.split('/')[2];
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ProductDetailPage(productId: productId),
          );
        }

        // Handle dynamic store routes
        if (settings.name?.startsWith('/store/') ?? false) {
          final sellerId = settings.name!.split('/')[2];
          final args = settings.arguments as Map<String, dynamic>?;
          final sellerData = args?['sellerData'] as Map<String, dynamic>?;
          final initialCategoryIds = (args?['initialCategoryIds'] as List?)
              ?.cast<String>();
          final initialSubCategoryIds =
              (args?['initialSubCategoryIds'] as List?)?.cast<String>();

          return MaterialPageRoute(
            settings: settings,
            builder: (context) => StorePage(
              sellerId: sellerId,
              sellerData: sellerData,
              initialCategoryIds: initialCategoryIds,
              initialSubCategoryIds: initialSubCategoryIds,
            ),
          );
        }

        // Handle reset password route
        // Web/large screens use ChangePasswordStandalonePage for better UI
        // Mobile uses ResetPasswordPage for mobile-optimized experience
        if (settings.name == '/reset-password') {
          final args = settings.arguments as Map<String, dynamic>?;
          final oobCode = args?['oobCode'] as String?;

          if (kIsWeb) {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) =>
                  ChangePasswordStandalonePage(oobCode: oobCode ?? ''),
            );
          } else {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => ResetPasswordPage(oobCode: oobCode ?? ''),
            );
          }
        }

        // Handle edit product route
        if (settings.name == '/edit-product') {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args != null && args['productId'] != null) {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => FutureBuilder<Product?>(
                future: _getProductForEdit(args['productId']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasData && snapshot.data != null) {
                    return EditProductPage(product: snapshot.data!);
                  }

                  return const Scaffold(
                    body: Center(child: Text('Product not found')),
                  );
                },
              ),
            );
          }
        }

        // Default to AuthWrapper for unknown routes
        // But during signup flow, ignore unknown routes to prevent
        // navigation away from the signup screen (e.g. from reCAPTCHA callback URLs)
        if (SignupState.isInSignupFlow) {
          AppLogger.d(
            'onGenerateRoute: Unknown route "${settings.name}" ignored during signup flow',
          );
          return null;
        }
        AppLogger.d(
          'onGenerateRoute: Unknown route "${settings.name}" -> AuthWrapper',
        );
        return MaterialPageRoute(
          settings: settings,
          builder: (context) => const AuthWrapper(),
        );
      },
      debugShowCheckedModeBanner: false,
    );

    // Publishes the appearance into the tree so every route below rebuilds
    // when it changes, rather than only when the OS brightness flips.
    final app = AppearanceScope(
      controller: ThemeController.instance,
      child: materialApp,
    );

    // Wrap with InAppNotificationWrapper only for mobile platforms
    if (!kIsWeb) {
      return InAppNotificationWrapper(
        notificationStream: NotificationService().messageStream,
        child: app,
      );
    }

    return app;
  }

  /// Builds `/cart/checkout/success` and `/cart/checkout/fail` — and the legacy
  /// `/payment-success` / `/payment-failed` — or null when [settings] names
  /// something else.
  ///
  /// These are the one pair of routes that a *browser* navigates to rather than
  /// the app: the payment provider redirects to them and hangs the order and
  /// session ids off the query string. `getCurrentPath` reports only the
  /// pathname, so on a cold load the ids are not in the route name at all and
  /// have to come from [_launchQueryParameters], captured before the address
  /// bar was rewritten.
  Route<dynamic>? _checkoutOutcomeRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;
    final uri = Uri.tryParse(name);
    if (uri == null) return null;

    final succeeded =
        uri.path == kCheckoutSuccessPath || uri.path == '/payment-success';
    final failed =
        uri.path == kCheckoutFailedPath || uri.path == '/payment-failed';
    if (!succeeded && !failed) return null;

    // The route's own query wins where both carry a key: it was set by this
    // app, whereas the launch parameters may be left over from the redirect
    // that started the session.
    final params = {..._launchQueryParameters, ...uri.queryParameters};

    return MaterialPageRoute(
      settings: settings,
      builder: (context) => succeeded
          ? PaymentSuccessPage(
              orderId: params['order_id'],
              sessionId:
                  params['session_id'] ?? params['payment_intent_id'],
            )
          : PaymentFailedPage(
              orderId: params['order_id'],
              sessionId: params['session_id'],
              errorMessage: params['error'] ?? params['message'],
            ),
    );
  }

  // Helper method to get product for editing
  Future<Product?> _getProductForEdit(String productId) async {
    final productService = ProductService();
    return await productService.getProductById(productId);
  }

  String _getInitialRoute() {
    if (kIsWeb) {
      final currentPath = getCurrentPath();

      // Read once, here, while the address bar still holds what the app was
      // launched with. By the time a route is built the shell has already
      // rewritten it, and a payment redirect's ids would be gone.
      _launchQueryParameters = getUrlQueryParameters();

      // A shell destination is a tab, not a route of its own. Handing '/cart'
      // to `initialRoute` would make Navigator build the stack ['/', '/cart']
      // and stack a second, back-buttoned copy of the app over the first — so
      // note which tab was asked for and let AppShell open it on mount.
      final shellTab = shellTabForPath(currentPath);
      if (shellTab != null) {
        pendingShellTab = shellTab;
        return '/';
      }

      // Anything under /cart/checkout. These cannot be handed to
      // `initialRoute`: Navigator would build the stack segment by segment and
      // '/cart' is a shell destination, so it would stack a second copy of the
      // app underneath. The shell opens on the Cart tab instead, and pushes
      // the checkout page on top of it once it has mounted.
      if (isCheckoutPath(currentPath)) {
        pendingShellTab = ShellTab.cart;
        // Only the two endings survive a cold load — the form and the payment
        // session both need state the previous screen was holding. Everything
        // else simply lands on the cart.
        if (isCheckoutOutcomePath(currentPath)) {
          pendingShellRoute = currentPath;
        }
        return '/';
      }

      // Legacy payment routes. Still the redirect targets configured with
      // PayMongo, so they have to keep working; unlike the paths above they
      // are top-level, so Navigator can build them directly.
      if (currentPath == '/payment-success' ||
          currentPath == '/payment-failed') {
        return currentPath;
      }
      // Top-level pages Navigator can build straight from the path: one
      // segment each, no arguments, and none of them the shell — so there is
      // no intermediate segment for Navigator to stack a second app under.
      //
      // '/home' is deliberately absent even though it is a registered route:
      // it builds the shell, and as `initialRoute` it would make Navigator
      // build ['/', '/home'] — two shells, one on top of the other. It is
      // handled above as a shell destination instead.
      const validRoutes = ['/login', '/auth', '/products', '/add-product'];
      if (validRoutes.contains(currentPath)) {
        return currentPath;
      }
      // For product detail routes
      if (currentPath.startsWith('/product/')) {
        return currentPath;
      }
      // For store routes
      if (currentPath.startsWith('/store/')) {
        return currentPath;
      }
      // Pages pushed from Profile — Settings, Chats, Addresses. Unlike a shell
      // destination these are real routes, so the path is handed straight to
      // Navigator, which builds the stack segment by segment: '/profile/chats'
      // under '/profile/chats/<id>', so Back walks up the same way it would
      // have in the app. Profile is marked pending so the shell underneath is
      // on the right tab once that stack unwinds.
      if (currentPath.startsWith('/profile/')) {
        pendingShellTab = ShellTab.profile;
        // '/…/edit' names no record — which one to edit travels in route
        // arguments, and a cold load has none. Handing the path to Navigator
        // anyway means its last segment builds to null, and Navigator answers
        // that by reporting 'Could not navigate to initial route', disposing
        // every route it had already built, and dropping the buyer on Home.
        // Open the list the editor belongs to instead.
        const editSuffix = '/edit';
        if (currentPath.endsWith(editSuffix)) {
          return currentPath.substring(
            0,
            currentPath.length - editSuffix.length,
          );
        }
        return currentPath;
      }
    }
    // Default to home route
    return '/';
  }
}
