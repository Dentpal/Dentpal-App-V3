import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../product/services/user_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/services.dart';
import 'profile_page.dart';
import 'chats_page.dart';

/// Customer Support Representative Dashboard Page
/// This page provides a simplified dashboard with only Chats and Profile access.
class CsrDashboardPage extends StatefulWidget {
  const CsrDashboardPage({super.key, this.isStandalone = false});

  /// Flag to indicate if this page is used standalone (not within bottom navigation)
  final bool isStandalone;

  @override
  _CsrDashboardPageState createState() => _CsrDashboardPageState();
}

class _CsrDashboardPageState extends State<CsrDashboardPage>
    with AutomaticKeepAliveClientMixin<CsrDashboardPage> {
  final UserService _userService = UserService();

  String _userFirstName = 'Support';

  // Current page state - 0 for Chats, 1 for Profile
  int _currentPageIndex = 0;

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    AppLogger.d("CsrDashboardPage initState called");
  }

  @override
  void dispose() {
    AppLogger.d("CsrDashboardPage dispose called");
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _userFirstName = 'Support';
        });
      }
      return;
    }

    final firstName = await _userService.getUserFirstName();
    if (mounted) {
      setState(() {
        _userFirstName = firstName;
      });
    }
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
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.exit_to_app,
                    color: AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Exit App',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
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
                child: Text('Cancel', style: AppTextStyles.buttonMedium),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Only wrap with PopScope if used standalone (not within home page navigation)
    if (!widget.isStandalone) {
      return _buildScaffold();
    }

    return PopScope(
      // On web, allow normal browser navigation; on mobile, show exit confirmation
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Skip exit confirmation on web - browsers handle their own navigation
        if (kIsWeb) return;

        // If we're not on Chats page and standalone, go back to Chats first
        if (_currentPageIndex != 0 && mounted) {
          setState(() {
            _currentPageIndex = 0;
          });
          return;
        }

        // If we're on Chats or not standalone, show exit confirmation
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final isWideScreen = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Header for wide screens
          if (isWideScreen)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // LEFT: Welcome section
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.support_agent,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Customer Support',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Hi $_userFirstName',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // CENTER: Spacer
                    const Expanded(child: SizedBox()),

                    // RIGHT: Navigation buttons
                    Row(
                      children: [
                        // Chats button
                        GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _currentPageIndex = 0;
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 22,
                                color: _currentPageIndex == 0
                                    ? AppColors.primary
                                    : AppColors.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Chats',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: _currentPageIndex == 0
                                      ? AppColors.primary
                                      : AppColors.onSurface.withOpacity(0.7),
                                  fontWeight: _currentPageIndex == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Profile button
                        GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _currentPageIndex = 1;
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 22,
                                color: _currentPageIndex == 1
                                    ? AppColors.primary
                                    : AppColors.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Profile',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: _currentPageIndex == 1
                                      ? AppColors.primary
                                      : AppColors.onSurface.withOpacity(0.7),
                                  fontWeight: _currentPageIndex == 1
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // SliverAppBar for mobile/tablet only
          if (!isWideScreen)
            SliverAppBar(
              expandedHeight: 60,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.surface,
              automaticallyImplyLeading: widget.isStandalone,
              leading: widget.isStandalone
                  ? IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
                      // Use maybePop to trigger PopScope's onPopInvokedWithResult
                      // for consistent exit confirmation on both button and system back
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Customer Support',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Hi $_userFirstName',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.05),
                        AppColors.secondary.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Navigation tabs section for mobile only
          if (!isWideScreen)
            SliverToBoxAdapter(
              child: Container(
                color: AppColors.surface,
                child: Row(
                  children: [
                    // Chats tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _currentPageIndex = 0;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _currentPageIndex == 0
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Chats',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: _currentPageIndex == 0
                                  ? AppColors.primary
                                  : AppColors.onSurface.withValues(alpha: 0.6),
                              fontWeight: _currentPageIndex == 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Profile tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _currentPageIndex = 1;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _currentPageIndex == 1
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Profile',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: _currentPageIndex == 1
                                  ? AppColors.primary
                                  : AppColors.onSurface.withValues(alpha: 0.6),
                              fontWeight: _currentPageIndex == 1
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Page content
          SliverFillRemaining(child: _buildCurrentPage()),
        ],
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentPageIndex) {
      case 0:
        return const ChatsPage();
      case 1:
        return const ProfilePage(hideChats: true);
      default:
        return const ChatsPage();
    }
  }
}
