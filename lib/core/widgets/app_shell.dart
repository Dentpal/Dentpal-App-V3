import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/services/nav_badge_service.dart';
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
/// Notifications is a destination, not a pushed page: opening it from the rail
/// used to slide a whole new route over the shell, so it "opened" while every
/// other rail entry "switched". It is absent from the bottom bar — five items
/// is already the limit there — and reached on a phone from the bell on Home
/// and Profile.
enum ShellTab { home, categories, cart, orders, notifications, profile }

/// The browser path each destination answers to.
///
/// `Navigator` only ever reports the topmost *route's* name to the address
/// bar, and all six destinations live inside one route — so without this table
/// every tab shares a single URL and a reload always lands on Home. Kept
/// beside [ShellTab] so a new destination cannot be added without deciding
/// what it is called on the web.
const Map<ShellTab, String> kShellTabPaths = {
  ShellTab.home: '/home',
  ShellTab.categories: '/categories',
  ShellTab.cart: '/cart',
  ShellTab.orders: '/orders',
  ShellTab.notifications: '/notifications',
  ShellTab.profile: '/profile',
};

/// The destination [path] names, or null when it is not a shell destination.
ShellTab? shellTabForPath(String path) {
  final normalised = path.split('?').first.split('#').first;
  for (final entry in kShellTabPaths.entries) {
    if (entry.value == normalised) return entry.key;
  }
  return null;
}

/// Destination the launch URL asked for, handed over before the shell exists.
///
/// The shell mounts several frames into startup — behind auth and the role
/// lookup — so the launch path cannot simply be read when it builds: by then
/// the address bar has already been rewritten. Set once from `main`, consumed
/// by the first shell to mount.
ShellTab? pendingShellTab;

/// A route to push on top of [pendingShellTab] once the shell is up.
///
/// Some paths are neither a shell destination nor something `initialRoute` can
/// build: `/cart/checkout/success` is one route deep under a *tab*, and handing
/// it to Navigator would make it build '/cart' as an intermediate segment and
/// stack a second copy of the app under the page. So the tab opens normally and
/// the rest of the path is pushed on top of it — which also gives Back somewhere
/// sensible to go, rather than nowhere.
///
/// Set from `main` alongside [pendingShellTab]; consumed once the session has
/// been settled, for the same reason the tab is.
String? pendingShellRoute;

/// Reselecting Home bumps this. [ProductListingPage] listens and scrolls itself
/// back to the top, the way tapping the active tab behaves in a native app.
/// A counter rather than a flag so consecutive taps each register.
final ValueNotifier<int> homeReselectTick = ValueNotifier<int>(0);

/// The destination currently on screen.
///
/// Kept-alive tabs are the whole point of the shell, but they come with a
/// blind spot: a page that is never rebuilt and never re-runs `initState` has
/// no way to notice it is being looked at again. Anything that must be
/// re-checked on re-entry — a cart another page marked stale, a profile edited
/// from Settings — watches this rather than refetching on every build.
final ValueNotifier<ShellTab> activeShellTab = ValueNotifier<ShellTab>(
  ShellTab.home,
);

/// Calls [onShellTabResumed] each time this page's tab is brought back into
/// view.
///
/// Deliberately silent for a *pushed* copy of the same page: a pushed route is
/// a sibling of the shell rather than a descendant, and it got a fresh
/// `initState` when it was pushed, so it has nothing to catch up on.
mixin ShellTabResume<T extends StatefulWidget> on State<T> {
  /// Which destination this page is mounted as.
  ShellTab get shellTab;

  /// Called when [shellTab] becomes visible again — never on first mount.
  ///
  /// Keep the work here conditional: this fires on every return to the tab,
  /// so it should decide whether a refetch is warranted, not perform one
  /// unconditionally.
  void onShellTabResumed();

  @override
  void initState() {
    super.initState();
    activeShellTab.addListener(_handleActiveShellTabChanged);
  }

  @override
  void dispose() {
    activeShellTab.removeListener(_handleActiveShellTabChanged);
    super.dispose();
  }

  void _handleActiveShellTabChanged() {
    if (!mounted) return;
    if (activeShellTab.value != shellTab) return;
    // Null when this page was pushed rather than mounted as a tab.
    if (AppShell.of(context) == null) return;
    onShellTabResumed();
  }
}

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

  /// Opens the notification inbox from anywhere in the app.
  ///
  /// Inside the shell that means switching to its tab; from a route that has
  /// covered the shell it means popping back to it first. Falls back to a push
  /// only when there is no shell at all.
  static void openNotifications(BuildContext context) {
    final shell = AppShell.of(context) ?? AppShell.instance;
    if (shell != null) {
      shell.openTab(ShellTab.notifications);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }

  /// The live shell, for code that is *not* below it in the tree.
  ///
  /// Pushed routes belong to the root navigator, so they are siblings of the
  /// shell rather than its descendants and [of] cannot find it. Null before the
  /// shell mounts, and while the app sits on a signed-out route.
  static AppShellState? instance;

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
    ShellTab.notifications,
    ShellTab.profile,
  };

  ShellTab get currentTab => _tab;

  /// A deep-linked destination that needs an account, parked until the first
  /// auth event says whether there is one. Null the rest of the time.
  ShellTab? _pendingTab;

  StreamSubscription<User?>? _authSubscription;
  String? _uid;

  @override
  void initState() {
    super.initState();
    AppShell.instance = this;
    NavBadgeService.instance.start();

    _adoptDeepLinkedTab();

    _uid = FirebaseAuth.instance.currentUser?.uid;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final accountChanged = user?.uid != _uid;
      _uid = user?.uid;
      if (!mounted) return;

      if (accountChanged) {
        // The account changed. Kept-alive tabs are holding the previous user's
        // cart, orders and profile, so drop them: they rebuild on next
        // selection against the new session.
        setState(() {
          _tab = ShellTab.home;
          _materialised
            ..clear()
            ..add(ShellTab.home);
          // Held page widgets belong to the previous session too; dropping
          // them is what makes the next selection build against the new
          // account.
          _pageCache.clear();
          _homeEpoch++;
          activeShellTab.value = ShellTab.home;
        });
      }

      // Either way, this is the first point at which a gated deep link can be
      // judged. When there was none, the reset above still needs the address
      // bar brought back in line.
      if (!_settlePendingTab() && accountChanged) syncBrowserUrl();
    });
  }

  /// Takes the destination the launch URL asked for, if there was one.
  ///
  /// It is held in [_pendingTab] either way, because on web the shell mounts
  /// before Firebase has restored the session:
  ///
  ///  * a gated destination (/cart, /orders…) cannot even be opened yet —
  ///    `currentUser` is still null, so opening it now would raise the login
  ///    prompt at someone who is in fact signed in;
  ///  * an ungated one can, but the session landing a moment later counts as
  ///    an account change and resets the shell to Home, which would throw the
  ///    request away.
  ///
  /// Both are settled on the first auth event, once there is an answer.
  void _adoptDeepLinkedTab() {
    final requested = pendingShellTab;
    pendingShellTab = null;

    if (requested == null || requested == ShellTab.home) {
      // Nothing to hang a pushed route off — drop it rather than letting it
      // land on a later, unrelated tab change.
      pendingShellRoute = null;
      _syncBrowserUrlAfterFirstFrame();
      return;
    }

    _pendingTab = requested;
    if (!_canOpen(requested)) {
      // Leave the address bar reading /orders until auth has its say; it is
      // corrected there if the visitor turns out to be signed out.
      return;
    }

    _tab = requested;
    _materialised.add(requested);
    activeShellTab.value = requested;
    _syncBrowserUrlAfterFirstFrame();
  }

  /// The initial route is '/', and the Navigator announces that name to the
  /// engine as it settles its history — so the tab's path has to be written
  /// after that, or it is simply overwritten.
  void _syncBrowserUrlAfterFirstFrame() {
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncBrowserUrl();
    });
  }

  /// Resolves a deep link that was waiting on the session, reporting whether
  /// there was one to resolve.
  bool _settlePendingTab() {
    final tab = _pendingTab;
    if (tab == null) return false;
    _pendingTab = null;

    if (_canOpen(tab)) {
      _showTab(tab);
      _settlePendingRoute();
    } else {
      // Signed out after all. The address bar still reads /orders, so point it
      // at what is actually on screen.
      pendingShellRoute = null;
      syncBrowserUrl();
    }
    return true;
  }

  /// Pushes [pendingShellRoute] over the tab that has just opened.
  ///
  /// After the frame, because `_showTab` has only just called `setState` and
  /// the tab underneath should be built before something lands on top of it —
  /// otherwise Back from the pushed page reveals a tab mid-build.
  void _settlePendingRoute() {
    final route = pendingShellRoute;
    pendingShellRoute = null;
    if (route == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamed(route);
    });
  }

  /// Points the address bar at the destination on screen, leaving the route
  /// stack alone.
  ///
  /// Replaces the current history entry rather than adding one: the six
  /// destinations share a single Flutter route, so a browser Back that stepped
  /// between tabs would be popping entries the `Navigator` knows nothing
  /// about. (The engine is in single-entry mode here regardless — `Navigator`
  /// selects it whenever it reports routes itself — so `replace` is stating
  /// what already happens.)
  void syncBrowserUrl() {
    if (!kIsWeb) return;
    final path = kShellTabPaths[_tab];
    if (path == null) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(path),
      replace: true,
    );
  }

  /// Bumped when the account changes, to re-key the Home tab so it too is
  /// rebuilt rather than showing the previous user's greeting and orders.
  int _homeEpoch = 0;

  @override
  void dispose() {
    if (AppShell.instance == this) AppShell.instance = null;
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Switches tabs, gating the ones that need an account.
  ///
  /// Returns false when the switch was refused, so callers that were about to
  /// do something else as well (apply a filter, say) can bail out too.
  bool selectTab(ShellTab tab) {
    if (!_canOpen(tab)) {
      _showLoginRequiredDialog();
      return false;
    }

    if (tab == _tab) {
      if (tab == ShellTab.home) homeReselectTick.value++;
      return true;
    }

    _showTab(tab);
    return true;
  }

  /// Whether [tab] is reachable for the current session.
  bool _canOpen(ShellTab tab) =>
      !_requiresAuth.contains(tab) ||
      FirebaseAuth.instance.currentUser != null;

  /// Brings [tab] on screen. The gate is the caller's business.
  void _showTab(ShellTab tab) {
    setState(() {
      _tab = tab;
      _materialised.add(tab);
    });
    // After setState, so a page reacting to this sees a shell that already
    // agrees it is the visible tab.
    activeShellTab.value = tab;
    syncBrowserUrl();
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

  /// Switches to [tab], leaving any pushed route on the way out.
  ///
  /// Tapping "Cart" in the rail while reading a notification should land on the
  /// cart, not on the cart *underneath* the notification.
  void openTab(ShellTab tab) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    selectTab(tab);
  }

  // ── Tab stack ────────────────────────────────────────────────────────────

  /// The widget for each materialised tab, built once and held.
  ///
  /// [build] runs on every tab switch, and rebuilding these six children from
  /// scratch each time rebuilt every *hidden* page too — which is how pages
  /// that create a `Future` or a `Stream` inside their own `build` ended up
  /// re-reading Firestore purely because the buyer glanced at another tab.
  /// Handing back the identical widget instance instead makes Flutter skip the
  /// subtree outright: an element whose new widget is identical to its old one
  /// is not rebuilt at all.
  final Map<ShellTab, Widget> _pageCache = {};

  Widget _pageFor(ShellTab tab) => _pageCache[tab] ??= _buildPage(tab);

  Widget _buildPage(ShellTab tab) {
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
      case ShellTab.notifications:
        return const NotificationsPage();
      case ShellTab.profile:
        return const ProfilePage();
    }
  }

  Widget _buildTabStack() {
    return IndexedStack(
      index: _tab.index,
      children: [
        for (final tab in ShellTab.values)
          // Hidden tabs stay mounted — that is the point of keeping them — and
          // `IndexedStack` maintains their animations, so a tab left on a
          // shimmering skeleton or an auto-scrolling banner went on asking for
          // a frame every 16ms for the rest of the session while invisible.
          // Muting the ticker parks those until the tab is looked at again.
          TickerMode(
            enabled: tab == _tab,
            child: _materialised.contains(tab)
                ? _pageFor(tab)
                : const SizedBox.shrink(),
          ),
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
                  ShellSideRail(activeTab: _tab),
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

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showLoginRequiredDialog() {
    final ink = InkPalette.of(context);
    final muted = ink.text.withValues(alpha: 0.6);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.login, color: ink.emerald),
            const SizedBox(width: 8),
            Text('Sign in required', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'You need to be signed in to use this. Sign in now?',
          style: AppTextStyles.bodyMedium.copyWith(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Not now', style: TextStyle(color: muted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pushNamed('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              elevation: 0,
            ),
            child: const Text('Sign in'),
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
  final ink = InkPalette.of(context);
  final muted = ink.text.withValues(alpha: 0.6);

  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: ink.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              // Amber: leaving is not destructive, but it is the one thing on
              // screen that needs a second look.
              Icon(Icons.exit_to_app, color: ink.amber),
              const SizedBox(width: 8),
              Text('Exit app', style: TextStyle(color: ink.text)),
            ],
          ),
          content: Text(
            'Are you sure you want to exit the app?',
            style: AppTextStyles.bodyMedium.copyWith(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Stay', style: TextStyle(color: muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.amber,
                foregroundColor: ink.onAmber,
                elevation: 0,
              ),
              child: const Text('Exit'),
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

/// The buyer shell's side rail.
///
/// Lives outside [AppShellState] so a *pushed* page can show it too: on a wide
/// window the rail is permanent chrome, and it used to vanish the moment you
/// opened Notifications from it. Tapping a tab from such a page pops back to
/// the shell and switches to it, via [AppShell.instance].
class ShellSideRail extends StatelessWidget {
  const ShellSideRail({super.key, this.activeTab});

  /// Destination to light up.
  final ShellTab? activeTab;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

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
                    _railTab(
                      ink: ink,
                      tab: ShellTab.home,
                      icon: Icons.home_rounded,
                      label: 'Home',
                    ),
                    _railTab(
                      ink: ink,
                      tab: ShellTab.categories,
                      icon: Icons.grid_view_rounded,
                      label: 'Categories',
                    ),
                    _railTab(
                      ink: ink,
                      tab: ShellTab.cart,
                      icon: Icons.shopping_cart_outlined,
                      label: 'Cart',
                      badge: NavBadgeService.instance.cartCount,
                    ),
                    _railTab(
                      ink: ink,
                      tab: ShellTab.orders,
                      icon: Icons.receipt_long_outlined,
                      label: 'Orders',
                    ),
                    _railTab(
                      ink: ink,
                      tab: ShellTab.notifications,
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      badge: NavBadgeService.instance.unreadNotifications,
                    ),
                    _railTab(
                      ink: ink,
                      tab: ShellTab.profile,
                      icon: Icons.person_outline,
                      label: 'Profile',
                    ),
                    const Spacer(),
                    _railItem(
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

  Widget _railTab({
    required InkPalette ink,
    required ShellTab tab,
    required IconData icon,
    required String label,
    ValueListenable<int>? badge,
  }) {
    return _railItem(
      ink: ink,
      icon: icon,
      label: label,
      badge: badge,
      isActive: activeTab == tab,
      onTap: () => AppShell.instance?.openTab(tab),
    );
  }

  Widget _railItem({
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
}

/// Puts the shell's URL back after a pushed route closes.
///
/// `Navigator` announces the topmost *named* route to the engine, so opening a
/// product from the Cart tab correctly writes /product/xyz — but closing it
/// announces the shell's own route name, '/', and the tab's path is lost. This
/// restores it as soon as the shell is on top again. Pushed routes built
/// without a `name` never announce anything, so those are unaffected either
/// way.
class ShellUrlObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _restoreIfShellIsBack(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _restoreIfShellIsBack(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _restoreIfShellIsBack(newRoute);

  void _restoreIfShellIsBack(Route<dynamic>? route) {
    if (!kIsWeb || route == null || !route.isFirst) return;
    // Deferred so the Navigator's own announcement of '/' — made while it
    // flushes this same history change — does not land on top of ours.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AppShell.instance?.syncBrowserUrl(),
    );
  }
}
