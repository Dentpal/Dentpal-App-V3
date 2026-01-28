import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb check
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../login_page.dart';
import '../../product/services/user_service.dart';
import 'shipping_addresses_page.dart';
import 'orders_page.dart';
//import 'seller_listings_page.dart';
import 'chats_page.dart';
import 'settings/settings_page.dart';
import 'settings/notifications_page.dart';
import 'package:dentpal/utils/app_logger.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.hideChats = false});

  /// When true, hides the Chats option from the profile menu.
  /// Used when ProfilePage is displayed within SellerDashboardPage which has its own Chats tab.
  final bool hideChats;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userCache;
  Map<String, dynamic>? _sellerCache;
  bool _hasLoadedData = false;

  Future<Map<String, dynamic>> _getUserData() async {
    if (_hasLoadedData && _userCache != null) {
      return {'user': _userCache, 'seller': _sellerCache};
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get user data
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _userCache = userDoc.data();

          // If user is a seller, get seller data
          if (_userCache?['role'] == 'seller') {
            final sellerDoc = await FirebaseFirestore.instance
                .collection('Seller')
                .doc(user.uid)
                .get();

            if (sellerDoc.exists) {
              _sellerCache = sellerDoc.data();
            }
          }
          _hasLoadedData = true;
        }
      }
    } catch (e) {
      AppLogger.d('Error loading user data: $e');
    }

    return {'user': _userCache, 'seller': _sellerCache};
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      // Clear UserService cache before signing out
      UserService.clearCache();
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showSignOutConfirmation(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.logout, color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Sign Out',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out?',
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
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Sign Out', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );

    if (shouldSignOut == true && context.mounted) {
      await _signOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Build the main body content (mobile layout retained exactly)
    Widget buildBody(
      Map<String, dynamic>? userData,
      Map<String, dynamic>? sellerData,
    ) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Profile Avatar
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 60,
                backgroundColor: AppColors.primary,
                backgroundImage:
                    userData?['photoURL'] != null &&
                        userData!['photoURL'].toString().isNotEmpty
                    ? NetworkImage(userData['photoURL'])
                    : null,
                child:
                    userData?['photoURL'] == null ||
                        userData!['photoURL'].toString().isEmpty
                    ? Icon(Icons.person, size: 60, color: AppColors.onPrimary)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            // User Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Full Name
                  Text(
                    userData?['displayName'] ?? user?.displayName ?? 'User',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Email
                  Text(
                    user?.email ?? 'No email',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Role/Status display
                  _buildRoleDisplay(userData, sellerData),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Profile Options
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (userData?['role'] == 'buyer') ...[
                    _buildProfileOption(
                      context,
                      'My Orders',
                      Icons.shopping_bag_outlined,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const OrdersPage(),
                          ),
                        );
                      },
                    ),
                    _buildDivider(),
                  ],
                  // Chats option - hidden when hideChats is true (e.g., in SellerDashboardPage)
                  if (!widget.hideChats) ...[
                    _buildProfileOption(
                      context,
                      'Chats',
                      Icons.chat_bubble_outline,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ChatsPage(),
                          ),
                        );
                      },
                    ),
                    _buildDivider(),
                  ],
                  if (userData?['role'] == 'buyer') ...[
                    _buildProfileOption(
                      context,
                      'Shipping Addresses',
                      Icons.location_on_outlined,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ShippingAddressesPage(),
                          ),
                        );
                      },
                    ),
                    _buildDivider(),

                    // _buildProfileOption(
                    //   context,
                    //   'Payment Methods',
                    //   Icons.payment_outlined,
                    //   () {
                    //     ScaffoldMessenger.of(context).showSnackBar(
                    //       SnackBar(
                    //         content: const Text(
                    //           'Payment methods feature coming soon',
                    //         ),
                    //         backgroundColor: AppColors.primary,
                    //       ),
                    //     );
                    //   },
                    // ),
                    // _buildDivider(),
                  ],
                  _buildProfileOption(
                    context,
                    'Settings',
                    Icons.settings_outlined,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                  _buildDivider(),
                  _buildProfileOption(
                    context,
                    'Notifications',
                    Icons.notifications_outlined,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const NotificationsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _showSignOutConfirmation(context),
                icon: Icon(Icons.logout, size: 20),
                label: Text('Sign Out', style: AppTextStyles.buttonLarge),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.person, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'My Profile',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: AppColors.error),
            onPressed: () => _showSignOutConfirmation(context),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _getUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_hasLoadedData) {
            return const Center(child: CircularProgressIndicator());
          }
          final userData = snapshot.data?['user'] as Map<String, dynamic>?;
          final sellerData = snapshot.data?['seller'] as Map<String, dynamic>?;
          final content = buildBody(userData, sellerData);
          // Responsive: use original mobile layout for small widths (even on web),
          // and centered constrained layout only for large web widths.
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWideWeb =
                  kIsWeb && constraints.maxWidth > 800; // breakpoint
              if (isWideWeb) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Material(color: Colors.transparent, child: content),
                  ),
                );
              }
              // Mobile & narrow web: ensure content stretches to full available width
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: constraints.maxWidth, child: content),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRoleDisplay(
    Map<String, dynamic>? userData,
    Map<String, dynamic>? sellerData,
  ) {
    final role = userData?['role'] ?? 'buyer';

    if (role == 'buyer') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart, size: 16, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              'Buyer',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (role == 'seller') {
      final isActive = sellerData?['isActive'] ?? false;
      final activeStatus = isActive is bool
          ? isActive
          : (isActive.toString().toLowerCase() == 'true');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activeStatus
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeStatus ? Icons.store : Icons.store_mall_directory_outlined,
              size: 16,
              color: activeStatus ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              activeStatus ? 'Active Seller' : 'Inactive Seller',
              style: AppTextStyles.bodySmall.copyWith(
                color: activeStatus ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildProfileOption(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.onSurface.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        color: AppColors.onSurface.withValues(alpha: 0.1),
      ),
    );
  }
}
