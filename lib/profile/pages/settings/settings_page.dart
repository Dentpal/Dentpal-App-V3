import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../core/services/sub_account_service.dart';
import 'change_mobile_page.dart';
import 'change_password_page.dart';
import 'edit_profile_page.dart';
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
        final effectiveUid = SubAccountSessionManager.getEffectiveUserId();
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(effectiveUid)
            .get();

        if (userDoc.exists) {
          _userCache = userDoc.data();
          _hasLoadedData = true;
        }
      }
    } catch (e) {
      AppLogger.d('Error loading user data: $e');
    }

    return _userCache;
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _getUserData(),
              builder: (context, snapshot) {
                final loading =
                    snapshot.connectionState == ConnectionState.waiting &&
                    !_hasLoadedData;
                final userRole = snapshot.data?['role'] ?? 'buyer';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildBody(userRole),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    28,
  );

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return const AppPageHeader(
      title: 'Settings',
      subtitle: 'Account, legal and privacy',
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(String userRole) {
    final showAccountSettings = !SubAccountSessionManager.isSubAccount;

    return ListView(
      padding: _listPadding,
      children: [
        if (showAccountSettings) ...[
          _buildSectionHeader('Account Settings'),
          const SizedBox(height: 12),
          _buildCard([
            _menuRow(
              icon: Icons.phone_outlined,
              label: 'Change mobile number',
              detail: 'Update the number on your account',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChangeMobilePage(),
                ),
              ),
            ),
            _menuRow(
              icon: Icons.lock_outline,
              label: 'Change password',
              detail: 'Keep your account secure',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChangePasswordPage(),
                ),
              ),
            ),
            if (userRole == 'buyer')
              _menuRow(
                icon: Icons.person_outline,
                label: 'Edit profile',
                detail: 'Name, photo and personal info',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage(),
                  ),
                ),
              ),
            if (userRole == 'seller')
              _menuRow(
                icon: Icons.store_outlined,
                label: 'Edit seller profile',
                detail: 'Store name, logo and details',
                onTap: () => _showComingSoonSnackBar('Edit seller profile'),
              ),
          ]),
          const SizedBox(height: 24),
        ],

        _buildSectionHeader('Legal & Privacy'),
        const SizedBox(height: 12),
        _buildCard([
          _menuRow(
            icon: Icons.description_outlined,
            label: 'Terms and Conditions',
            detail: 'What you agree to when using DentPal',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const TermsConditionsPage(),
              ),
            ),
          ),
          _menuRow(
            icon: Icons.shield_outlined,
            label: 'Privacy Policy',
            detail: 'How we handle your data',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PrivacyPolicyPage(),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: ink.text.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> rows) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Divider(height: 1, color: ink.border),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required String detail,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: ink.emerald, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: ink.text.withValues(alpha: 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoonSnackBar(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature coming soon'),
        backgroundColor: ink.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
