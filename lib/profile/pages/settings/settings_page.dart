import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import 'change_mobile_page.dart';
import 'change_password_page.dart';
import 'data_privacy_page.dart';
import 'terms_conditions_page.dart';
import 'privacy_policy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _userCache;
  bool _hasLoadedData = false;

  Future<Map<String, dynamic>?> _getUserData() async {
    if (_hasLoadedData && _userCache != null) {
      return _userCache;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          _userCache = userDoc.data();
          _hasLoadedData = true;
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }

    return _userCache;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.settings, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Settings',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _getUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !_hasLoadedData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final userData = snapshot.data;
          final userRole = userData?['role'] ?? 'buyer';
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                
                // Account Settings Section
                _buildSectionHeader('Account Settings'),
                const SizedBox(height: 16),
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
                      _buildSettingsOption(
                        context,
                        'Change Mobile Number',
                        Icons.phone_outlined,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ChangeMobilePage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsOption(
                        context,
                        'Change Password',
                        Icons.lock_outline,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ChangePasswordPage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsOption(
                        context,
                        'Edit Profile',
                        Icons.person_outline,
                        () {
                          _showComingSoonSnackBar(context, 'Edit profile');
                        },
                      ),
                      // Show Edit Seller Profile only for sellers
                      if (userRole == 'seller') ...[
                        _buildDivider(),
                        _buildSettingsOption(
                          context,
                          'Edit Seller Profile',
                          Icons.store_outlined,
                          () {
                            _showComingSoonSnackBar(context, 'Edit seller profile');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Business Settings Section (for non-sellers)
                if (userRole != 'seller') ...[
                  _buildSectionHeader('Business'),
                  const SizedBox(height: 16),
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
                    child: _buildSettingsOption(
                      context,
                      'Upgrade to Seller Account',
                      Icons.trending_up_outlined,
                      () {
                        _showComingSoonSnackBar(context, 'Upgrade to seller account');
                      },
                      isPromoted: true,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                
                // Legal & Privacy Section
                _buildSectionHeader('Legal & Privacy'),
                const SizedBox(height: 16),
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
                      _buildSettingsOption(
                        context,
                        'Data Privacy',
                        Icons.privacy_tip_outlined,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const DataPrivacyPage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsOption(
                        context,
                        'Terms and Conditions',
                        Icons.description_outlined,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const TermsConditionsPage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsOption(
                        context,
                        'Privacy Policy',
                        Icons.shield_outlined,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PrivacyPolicyPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
  
  Widget _buildSettingsOption(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool isPromoted = false,
  }) {
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
                  color: isPromoted 
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isPromoted ? AppColors.success : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isPromoted ? AppColors.success : null,
                  ),
                ),
              ),
              if (isPromoted) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NEW',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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

  void _showComingSoonSnackBar(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature coming soon'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}