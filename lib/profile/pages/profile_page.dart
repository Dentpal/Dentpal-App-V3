import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../login_page.dart';
import 'shipping_addresses_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // Static cache to persist data across rebuilds
  static Map<String, dynamic>? _userCache;
  static Map<String, dynamic>? _sellerCache;
  static bool _hasLoadedData = false;

  Future<Map<String, dynamic>> _getUserData() async {
    if (_hasLoadedData && _userCache != null) {
      return {
        'user': _userCache,
        'seller': _sellerCache,
      };
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
      debugPrint('Error loading user data: $e');
    }

    return {
      'user': _userCache,
      'seller': _sellerCache,
    };
  }

  Future<void> _signOut(BuildContext context) async {
    try {
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
              child: Icon(
                Icons.logout,
                color: AppColors.error,
                size: 24,
              ),
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
          if (snapshot.connectionState == ConnectionState.waiting && !_hasLoadedData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final userData = snapshot.data?['user'] as Map<String, dynamic>?;
          final sellerData = snapshot.data?['seller'] as Map<String, dynamic>?;
          
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
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: AppColors.onPrimary,
                    ),
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
                      _buildProfileOption(
                        context,
                        'My Orders',
                        Icons.shopping_bag_outlined,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Orders feature coming soon'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
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
                      _buildProfileOption(
                        context,
                        'Payment Methods',
                        Icons.payment_outlined,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Payment methods feature coming soon'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildProfileOption(
                        context,
                        'Settings',
                        Icons.settings_outlined,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Settings feature coming soon'),
                              backgroundColor: AppColors.primary,
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
        },
      ),
    );
  }

  Widget _buildRoleDisplay(Map<String, dynamic>? userData, Map<String, dynamic>? sellerData) {
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
            Icon(
              Icons.shopping_cart,
              size: 16,
              color: AppColors.primary,
            ),
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
      final activeStatus = isActive is bool ? isActive : (isActive.toString().toLowerCase() == 'true');
      
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
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 20,
                ),
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
