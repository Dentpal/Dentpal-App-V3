import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:dentpal/core/app_theme/app_colors.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/services/nav_badge_service.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/product/pages/cart_page.dart';
import 'package:dentpal/product/pages/categories_page.dart';
import 'package:dentpal/product/pages/product_listing_page.dart';
import 'package:dentpal/profile/pages/orders_page.dart';
import 'package:dentpal/profile/pages/profile_page.dart';
import 'package:dentpal/profile/pages/settings/notifications_page.dart';
import 'package:dentpal/public_support_page.dart';

/// The buyer's five destinations, in tab-stack order.
///
/// The bottom bar draws them in a different *visual* order (Home in the middle)
/// but both surfaces index into this one list, so a destination can never mean
/// one thing to the rail and another to the bar.
enum ShellTab { home, categories, cart, orders, profile }

/// Reselecting Home bumps this. [ProductListingPage] listens and scrolls itself
/// back to the top, the way tapping the active tab behaves in a native app.
/// A counter rather than a flag so consecutive taps each register.
final ValueNotifier<int> homeReselectTick = ValueNotifier<int>(0);

/// The persistent chrome around the buyer's tabs.
///
/// Everything that must survive navigation lives here: the side rail, the
/// bottom bar, the badge counts and the tab stack itself. Pages are children of
/// this widget, so switching tabs never rebuilds the chrome and never disposes
/// the outgoing page.
///
/// Previously the rail was built *inside* the Home page and every other
/// destination was a `Navigator.push`, so the rail vanished the moment you left
/// Home and its active item was hardcoded to Home. Tabs were swapped with a
/// bare `body: _pages[index]`, which destroyed the outgoing page's state on
/// every switch — which in turn made the `AutomaticKeepAliveClientMixin` those
/// pages implement inert, since nothing above them honoured it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Lets a descendant page drive the shell — switch tabs, apply a browse
  /// selection — without threading callbacks through every constructor.
  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  ShellTab _tab = ShellTab.home;

  /// Which tabs have ever been selected. An `IndexedStack` builds every child
  /// immediately, so without this all five pages would fire their `initState`
  /// fetches at boot — strictly worse than the old behaviour. A tab renders as
  /// an empty box until first opened, and is kept alive forever after.
  final Set<ShellTab> _materialised = {ShellTab.home};

  /// Destinations that need an account. Home and Categories are browsable
  /// signed out.
  static const Set<ShellTab> _requiresAuth = {
    ShellTab.cart,
    ShellTab.orders,
    ShellTab.profile,
  };

  ShellTab get currentTab => _tab;

  StreamSubscription<User?>? _authSubscription;
  String? _uid;

  @override
  void initState() {
    super.initState();
    NavBadgeService.instance.start();

    _uid = FirebaseAuth.instance.currentUser?.uid;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _uid) return;
      _uid = user?.uid;

      // The account changed. Kept-alive tabs are holding the previous user's
      // cart, orders and profile, so drop them: they rebuild on next selection
      // against the new session.
      if (!mounted) return;
      setState(() {
        _tab = ShellTab.home;
        _materialised
          ..clear()
          ..add(ShellTab.home);
        _homeEpoch++;
      });
    });
  }

  /// Bumped when the account changes, to re-key the Home tab so it too is
  /// rebuilt rather than showing the previous user's greeting and orders.
  int _homeEpoch = 0;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Switches tabs, gating the ones that need an account.
  ///
  /// Returns false when the switch was refused, so callers that were about to
  /// do something else as well (apply a filter, say) can bail out too.
  bool selectTab(ShellTab tab) {
    if (_requiresAuth.contains(tab) &&
        FirebaseAuth.instance.currentUser == null) {
      _showLoginRequiredDialog();
      return false;
    }

    if (tab == _tab) {
      if (tab == ShellTab.home) homeReselectTick.value++;
      return true;
    }

    setState(() {
      _tab = tab;
      _materialised.add(tab);
    });
    return true;
  }

  /// Categories hands its pick to the listing page and brings it into view.
  ///
  /// As a tab, Categories can no longer `Navigator.pop` a result back to
  /// whoever pushed it, so the selection travels through
  /// [pendingBrowseSelection] — the listing page is a live sibling in the same
  /// stack, not something this widget holds a reference to.
  void applyBrowseSelection(BrowseSelection selection) {
    selectTab(ShellTab.home);
    pendingBrowseSelection.value = selection;
  }

  void _pushProtected(Widget page) {
    if (FirebaseAuth.instance.currentUser == null) {
      _showLoginRequiredDialog();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  // ── Tab stack ────────────────────────────────────────────────────────────

  Widget _pageFor(ShellTab tab) {
    switch (tab) {
      case ShellTab.home:
        // Re-keyed per account so signing in as someone else rebuilds it.
        return ProductListingPage(key: ValueKey('home-$_homeEpoch'));
      case ShellTab.categories:
        return const CategoriesPage();
      case ShellTab.cart:
        // A non-null onBackPressed is how CartPage tells "I am a tab" from "I
        // was pushed": as a tab it must not draw a back button, and "continue
        // shopping" switches tab rather than popping a route.
        return CartPage(onBackPressed: () => selectTab(ShellTab.home));
      case ShellTab.orders:
        return const OrdersPage();
      case ShellTab.profile:
        return const ProfilePage();
    }
  }

  Widget _buildTabStack() {
    return IndexedStack(
      index: _tab.index,
      children: [
        for (final tab in ShellTab.values)
          _materialised.contains(tab)
              ? _pageFor(tab)
              : const SizedBox.shrink(),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final isWide = context.isWideLayout;

    return PopScope(
      // A non-Home tab consumes the back gesture to return to Home; only Home
      // itself is allowed to leave the app. On web the browser owns this.
      canPop: kIsWeb && _tab == ShellTab.home,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_tab != ShellTab.home) {
          selectTab(ShellTab.home);
          return;
        }
        if (kIsWeb) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: ink.bg,
        body: isWide
            ? Row(
                children: [
                  _buildSideRail(ink),
                  Expanded(child: _buildTabStack()),
                ],
              )
            : _buildTabStack(),
        bottomNavigationBar: isWide ? null : _buildBottomBar(ink),
      ),
    );
  }

  // ── Bottom bar (narrow) ──────────────────────────────────────────────────

  /// Five destinations with Home in the middle. Unlike the old bar, every item
  /// now switches a tab — Categories and Orders used to push a full route that
  /// animated in over the bar, so two of five items moved differently from the
  /// rest and neither could ever show as active.
  Widget _buildBottomBar(InkPalette ink) {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _buildBarItem(
                ink: ink,
                tab: ShellTab.categories,
                icon: Icons.grid_view_rounded,
                label: 'Categories',
              ),
              _buildBarItem(
                ink: ink,
                tab: ShellTab.cart,
                icon: Icons.shopping_cart_outlined,
                activeIcon: Icons.shopping_cart,
                label: 'Cart',
                badge: NavBadgeService.instance.cartCount,
              ),
              _buildBarItem(
                ink: ink,
                tab: ShellTab.home,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
              ),
              _buildBarItem(
                ink: ink,
                tab: ShellTab.orders,
                icon: Icons.receipt_long_outlined,
                label: 'Orders',
              ),
              _buildBarItem(
                ink: ink,
                tab: ShellTab.profile,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarItem({
    required InkPalette ink,
    required ShellTab tab,
    required IconData icon,
    required String label,
    IconData? activeIcon,
    ValueListenable<int>? badge,
  }) {
    final isActive = _tab == tab;
    final color = isActive ? ink.emerald : ink.text.withValues(alpha: 0.55);

    return Expanded(
      child: InkWell(
        onTap: () => selectTab(tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? (activeIcon ?? icon) : icon,
                  size: 23,
                  color: color,
                ),
                if (badge != null)
                  Positioned(
                    right: -7,
                    top: -5,
                    child: _Badge(listenable: badge, ink: ink),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Side rail (wide) ─────────────────────────────────────────────────────

  Widget _buildSideRail(InkPalette ink) {
    return Container(
      width: kAppShellRailWidth,
      decoration: BoxDecoration(
        color: ink.bg,
        border: Border(right: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        // A short browser window would otherwise overflow the rail. Scrolls
        // only once it has to; `IntrinsicHeight` keeps the `Spacer` working
        // when there is room to spare.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                      child: Row(
                        children: [
                          Image.asset(
                            'lib/assets/icons/dentpal_icon.png',
                            width: 34,
                            height: 34,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'DentPal',
                            style: AppTextStyles.titleLarge.copyWith(
                              color: ink.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildRailTab(
                      ink: ink,
                      tab: ShellTab.home,
                      icon: Icons.home_rounded,
                      label: 'Home',
                    ),
                    _buildRailTab(
                      ink: ink,
                      tab: ShellTab.categories,
                      icon: Icons.grid_view_rounded,
                      label: 'Categories',
                    ),
                    _buildRailTab(
                      ink: ink,
                      tab: ShellTab.cart,
                      icon: Icons.shopping_cart_outlined,
                      label: 'Cart',
                      badge: NavBadgeService.instance.cartCount,
                    ),
                    _buildRailTab(
                      ink: ink,
                      tab: ShellTab.orders,
                      icon: Icons.receipt_long_outlined,
                      label: 'Orders',
                    ),
                    // Not a tab: notifications are a place you visit and leave,
                    // not one of the five you live in.
                    _buildRailItem(
                      ink: ink,
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      badge: NavBadgeService.instance.unreadNotifications,
                      onTap: () => _pushProtected(const NotificationsPage()),
                    ),
                    _buildRailTab(
                      ink: ink,
                      tab: ShellTab.profile,
                      icon: Icons.person_outline,
                      label: 'Profile',
                    ),
                    const Spacer(),
                    _buildRailItem(
                      ink: ink,
                      icon: Icons.headset_mic_outlined,
                      label: 'Support',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PublicSupportPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRailTab({
    required InkPalette ink,
    required ShellTab tab,
    required IconData icon,
    required String label,
    ValueListenable<int>? badge,
  }) {
    return _buildRailItem(
      ink: ink,
      icon: icon,
      label: label,
      badge: badge,
      isActive: _tab == tab,
      onTap: () => selectTab(tab),
    );
  }

  Widget _buildRailItem({
    required InkPalette ink,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    ValueListenable<int>? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: isActive
            ? ink.emerald.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: isActive
                      ? ink.emerald
                      : ink.text.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isActive
                          ? ink.emerald
                          : ink.text.withValues(alpha: 0.8),
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null)
                  _Badge(listenable: badge, ink: ink, pill: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          'You need to login to access this feature. '
          'Would you like to login now?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Cancel', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
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
      ),
    );
  }

  Future<bool> _showExitConfirmation() => showAppExitConfirmation(context);
}

/// "Are you sure you want to exit the app?"
///
/// Shared because the buyer shell and the seller/CSR shells all need it and
/// there is no reason for three copies of the same dialog.
Future<bool> showAppExitConfirmation(BuildContext context) async {
  return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
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
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
                ),
                child: Text('Cancel', style: AppTextStyles.buttonMedium),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
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

/// Width of the wide-screen side rail.
///
/// Public because pages laying out inside the shell need to know how much of
/// the viewport the rail has already claimed — `MediaQuery` still reports the
/// full window width to them.
const double kAppShellRailWidth = 248;

/// A count that repaints on its own rather than rebuilding the whole shell —
/// otherwise every cart tick would rebuild all five tabs' parent.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.listenable,
    required this.ink,
    this.pill = false,
  });

  final ValueListenable<int> listenable;
  final InkPalette ink;

  /// The rail draws a wide emerald pill; the bottom bar a small amber dot.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        final label = count > 99 ? '99+' : '$count';

        if (pill) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: const BoxConstraints(minWidth: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ink.emerald,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.onEmerald,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: ink.amber, shape: BoxShape.circle),
          child: Text(
            label,
            style: TextStyle(
              color: ink.onAmber,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
