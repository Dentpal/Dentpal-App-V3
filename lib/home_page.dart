import 'dart:async';

import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dentpal/product/pages/product_listing_page.dart';
import 'package:dentpal/product/pages/seller_dashboard_page.dart';
import 'package:dentpal/profile/pages/csr_dashboard_page.dart';
import 'package:dentpal/product/pages/cart_page.dart';
import 'package:dentpal/profile/pages/profile_page.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/app_theme/app_colors.dart';
import 'core/app_theme/app_text_styles.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isSeller = false;
  bool _isCustomerSupport = false;
  bool _isLoadingSellerStatus = true;
  StreamSubscription<User?>? _authSubscription;
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();

    _checkUserRole();

    // Listen to auth state changes to refresh user role
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      _checkUserRole();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      AppLogger.d('DEBUG _checkUserRole: user = ${user?.uid}');
      if (user == null) {
        setState(() {
          _isSeller = false;
          _isCustomerSupport = false;
          _isLoadingSellerStatus = false;
        });
        return;
      }

      // Force refresh to ensure we get fresh data after login
      // Check for customer support role first
      AppLogger.d('DEBUG: Checking customer support status...');
      final isCustomerSupport = await _userService.isCurrentUserCustomerSupport(
        forceRefresh: true,
      );
      AppLogger.d('DEBUG: isCustomerSupport = $isCustomerSupport');
      if (isCustomerSupport) {
        if (mounted) {
          AppLogger.d('DEBUG: Setting state for customer support');
          setState(() {
            _isSeller = false;
            _isCustomerSupport = true;
            _isLoadingSellerStatus = false;
          });
        }
        return;
      }

      // Check for seller role
      AppLogger.d('DEBUG: Checking seller status...');
      final isSeller = await _userService.isCurrentUserSeller(
        forceRefresh: true,
      );
      AppLogger.d('DEBUG: isSeller = $isSeller');

      if (mounted) {
        setState(() {
          _isSeller = isSeller;
          _isCustomerSupport = false;
          _isLoadingSellerStatus = false;
        });
      }
    } catch (e) {
      AppLogger.d('Error checking user role: $e');
      if (mounted) {
        setState(() {
          _isSeller = false;
          _isCustomerSupport = false;
          _isLoadingSellerStatus = false;
        });
      }
    }
  }

  List<Widget> get _pages {
    final user = FirebaseAuth.instance.currentUser;
    AppLogger.d(
      'DEBUG _pages: _isCustomerSupport=$_isCustomerSupport, _isSeller=$_isSeller',
    );

    if (_isCustomerSupport) {
      // Customer Support navigation - only CSR Dashboard (Chats + Profile)
      AppLogger.d('DEBUG: Returning CsrDashboardPage');
      return [const CsrDashboardPage()];
    } else if (_isSeller) {
      // Seller navigation - only My Products and Profile
      return [
        const SellerDashboardPage(), // My Products
        user != null
            ? const ProfilePage()
            : const _LoginRequiredPage(
                message: 'Please login to view your profile',
              ),
      ];
    } else {
      // Regular user navigation - Products, Cart, Profile
      return [
        const ProductListingPage(),
        user != null
            ? CartPage(
                onBackPressed: () => _onItemTapped(0),
              ) // Go back to Products tab
            : const _LoginRequiredPage(
                message: 'Please login to view your cart',
              ),
        user != null
            ? const ProfilePage()
            : const _LoginRequiredPage(
                message: 'Please login to view your profile',
              ),
      ];
    }
  }

  void _onItemTapped(int index) {
    // Check if user is authenticated when trying to access protected features
    final user = FirebaseAuth.instance.currentUser;

    if (_isCustomerSupport) {
      // For customer support: only CSR Dashboard (index 0)
      // CSR Dashboard has its own internal navigation for Chats and Profile
      if (user == null) {
        _showLoginRequiredDialog();
        return;
      }
    } else if (_isSeller) {
      // For sellers: only My Products (index 0) and Profile (index 1)
      if (user == null && index == 1) {
        // User is not authenticated and trying to access Profile
        _showLoginRequiredDialog();
        return;
      }
    } else {
      // For regular users: Products (0), Cart (1), Profile (2)
      if (user == null && (index == 1 || index == 2)) {
        // User is not authenticated and trying to access Cart or Profile
        _showLoginRequiredDialog();
        return;
      }
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.login, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'Login Required',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'You need to login to access this feature. Would you like to login now?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
              ),
              child: Text('Cancel', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Login', style: AppTextStyles.buttonMedium),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.exit_to_app,
                    color: AppColors.warning,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Exit App',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            content: Text(
              'Are you sure you want to exit the app?',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
                ),
                child: Text('Cancel', style: AppTextStyles.buttonMedium),
              ),
              ElevatedButton(
                onPressed: () {
                  SystemNavigator.pop(); // Sends to background or closes app
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                ),
                child: Text('Exit', style: AppTextStyles.buttonMedium),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 900;

    // Show loading while checking seller status
    if (_isLoadingSellerStatus) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      // On web, allow normal browser navigation; on mobile, show exit confirmation
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Skip exit confirmation on web - browsers handle their own navigation
        if (kIsWeb) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: isWebView
            ? Column(
                children: [
                  // Navigation bar removed; now handled in ProductListingPage sliver
                  Expanded(child: _pages[_selectedIndex]),
                ],
              )
            : Scaffold(
                body: _pages[_selectedIndex],
                // Only show bottom navigation bar for regular users
                // Sellers use SellerDashboardPage's internal navigation
                // Customer Support uses CsrDashboardPage's internal navigation
                bottomNavigationBar: (_isSeller || _isCustomerSupport)
                    ? null
                    : _buildBottomNavigationBar(),
              ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    if (_isSeller) {
      // Seller navigation - only My Products and Profile
      return BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'My Products',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        onTap: _onItemTapped,
      );
    } else {
      // Regular user navigation - Products, Cart, Profile
      return BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Products'),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Cart',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        onTap: _onItemTapped,
      );
    }
  }
}

class _LoginRequiredPage extends StatelessWidget {
  final String message;

  const _LoginRequiredPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(Icons.login, size: 64, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Login Required',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onBackground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.onBackground.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Login Now',
                  style: AppTextStyles.buttonLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Navigate back to products page
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  'Continue Browsing Products',
                  style: AppTextStyles.buttonMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
