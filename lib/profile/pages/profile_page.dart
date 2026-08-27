import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/widgets/app_shell.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_controller.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_page_header.dart';
import '../../login_page.dart';
import '../../core/services/nav_badge_service.dart';
import '../../core/services/session_cache.dart';
import '../../core/services/sub_account_service.dart';
import '../../core/widgets/skeleton.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/widgets/loading_skeletons.dart';
import '../../utils/currency_formatter.dart';
import '../services/order_service.dart';
import 'package:dentpal/utils/app_logger.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.hideChats = false});

  /// When true, hides the Chats option from the profile menu.
  /// Used when ProfilePage is displayed within SellerDashboardPage which has its own Chats tab.
  final bool hideChats;

  /// Marks the cached profile as out of date.
  ///
  /// As a tab of the shell this page is kept alive, so it no longer refetches
  /// merely by being navigated back to — which is the point, but it means an
  /// edit made elsewhere has to say so. Callers do not need the page to be
  /// mounted: the next time it is shown it re-reads because the cache is gone.
  static void invalidate() => _ProfilePageState.clearCache();

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with ShellTabResume<ProfilePage> {
  // Cached across instances, keyed by account: ProfilePage is a shell tab in
  // one place and a pushed route in another (seller dashboard), and both used
  // to pay for the same two document reads.
  static Map<String, dynamic>? _userCache;
  static Map<String, dynamic>? _sellerCache;
  static String? _cachedUid;
  static DateTime? _cachedAt;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Created once, in [initState].
  ///
  /// This used to be built inside `build()`, which meant a brand new Firestore
  /// read on every single rebuild — and a rebuild happened on every parent
  /// setState.
  late Future<Map<String, dynamic>> _userDataFuture;

  /// Orders behind the stats row. Separate from the profile read so a slow or
  /// failed order query never holds up the name and avatar.
  late Future<_ProfileStats> _statsFuture;

  bool get _hasLoadedData => _userCache != null && _isCacheFresh;

  static bool get _isCacheFresh {
    final at = _cachedAt;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return at != null &&
        uid != null &&
        _cachedUid == uid &&
        DateTime.now().difference(at) < _cacheDuration;
  }

  /// Drops the cached profile. Called on sign-out so the next account does not
  /// see the previous one's name and avatar, and by [ProfilePage.invalidate]
  /// after an edit.
  static void clearCache() {
    _userCache = null;
    _sellerCache = null;
    _cachedUid = null;
    _cachedAt = null;
  }

  @override
  void initState() {
    super.initState();
    _userDataFuture = _getUserData();
    _statsFuture = _loadStats();
  }

  @override
  ShellTab get shellTab => ShellTab.profile;

  /// Re-read the profile when the buyer returns to this tab and the cached
  /// copy has gone stale.
  ///
  /// The two futures are created once and the page is now kept alive, so
  /// without this nothing would ever re-read the profile after it was edited
  /// from Settings — the old name and avatar would stay on screen for the rest
  /// of the session. Editing clears [_cachedAt] via [clearCache], which is what
  /// makes the next return here refetch.
  ///
  /// Inside the cache window this is a no-op, so switching tabs is free; and
  /// because [_getUserData] serves the cache while the read is in flight, a
  /// refetch swaps the values in without ever showing the loading state.
  @override
  void onShellTabResumed() {
    if (_isCacheFresh) return;
    setState(() {
      _userDataFuture = _getUserData();
      _statsFuture = _loadStats();
    });
  }

  /// Orders placed, spend so far this year, and the year they joined.
  ///
  /// Reuses whatever the orders tab has already streamed this session, so
  /// opening Profile after Orders costs nothing.
  Future<_ProfileStats> _loadStats() async {
    final user = FirebaseAuth.instance.currentUser;
    final joined =
        (_userCache?['createdAt'] as Timestamp?)?.toDate() ??
        user?.metadata.creationTime;

    try {
      final orders =
          OrderService.cachedOrders ?? await OrderService.fetchUserOrders();
      final thisYear = DateTime.now().year;

      var spent = 0.0;
      for (final order in orders) {
        if (order.createdAt.year != thisYear) continue;
        if (_unpaidStatuses.contains(order.status)) continue;
        spent += order.summary.total;
      }

      return _ProfileStats(
        orderCount: orders.length,
        spentThisYear: spent,
        memberSince: joined,
      );
    } catch (e) {
      AppLogger.d('Error loading profile stats: $e');
      return _ProfileStats(memberSince: joined);
    }
  }

  /// Orders that never took money, so they do not count towards spend.
  static const Set<order_model.OrderStatus> _unpaidStatuses = {
    order_model.OrderStatus.pending,
    order_model.OrderStatus.cancelled,
    order_model.OrderStatus.payment_failed,
    order_model.OrderStatus.expired,
    order_model.OrderStatus.refunded,
    order_model.OrderStatus.returned,
  };

  Future<Map<String, dynamic>> _getUserData() async {
    if (_hasLoadedData) {
      return {'user': _userCache, 'seller': _sellerCache};
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final effectiveUid = SubAccountSessionManager.getEffectiveUserId();
        // Get user data
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(effectiveUid)
            .get();

        if (userDoc.exists) {
          _userCache = userDoc.data();

          // If user is a seller, get seller data
          if (_userCache?['role'] == 'seller') {
            final sellerDoc = await FirebaseFirestore.instance
                .collection('Seller')
                .doc(effectiveUid)
                .get();

            if (sellerDoc.exists) {
              _sellerCache = sellerDoc.data();
            }
          }
          _cachedUid = user.uid;
          _cachedAt = DateTime.now();
        }
      }
    } catch (e) {
      AppLogger.d('Error loading user data: $e');
    }

    return {'user': _userCache, 'seller': _sellerCache};
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

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
            child: FutureBuilder<Map<String, dynamic>>(
              future: _userDataFuture,
              builder: (context, snapshot) {
                // Falling back to the cache matters while a *stale* copy is
                // being refreshed: the future is new, so the snapshot is empty,
                // and without this the page would blink back to its skeleton
                // on re-entry despite already knowing the name and avatar.
                final userData =
                    snapshot.data?['user'] as Map<String, dynamic>? ??
                    _userCache;
                final sellerData =
                    snapshot.data?['seller'] as Map<String, dynamic>? ??
                    _sellerCache;
                final loading =
                    snapshot.connectionState == ConnectionState.waiting &&
                    userData == null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(userData),
                    Expanded(
                      child: loading
                          ? const ProfileSkeleton(padding: _listPadding)
                          : _buildBody(userData, sellerData),
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

  Widget _buildHeader(Map<String, dynamic>? userData) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    return AppPageHeader(
      title: 'Profile',
      subtitle: email != null && email.isNotEmpty
          ? 'Signed in as $email'
          : 'Your account',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const _NotificationBell(),
            // The inbox is a shell destination, so this switches to it instead
            // of stacking a second copy over the profile.
            onPressed: () => AppShell.openNotifications(context),
            tooltip: 'Notifications',
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: ink.text),
            onPressed: () =>
                Navigator.of(context).pushNamed('/profile/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(
    Map<String, dynamic>? userData,
    Map<String, dynamic>? sellerData,
  ) {
    return ListView(
      padding: _listPadding,
      children: [
        _buildIdentityCard(userData, sellerData),
        const SizedBox(height: 12),
        _buildStatsCard(),
        const SizedBox(height: 12),
        _buildAppearanceCard(),
        const SizedBox(height: 20),
        _buildMenuCard(userData),
        const SizedBox(height: 22),
        _buildSignOutButton(),
      ],
    );
  }

  /// Who is signed in: avatar, name, email and what this account is allowed to
  /// do. The avatar used to be a 120px circle floating above the card on its
  /// own; beside the name it says the same thing in half the height.
  Widget _buildIdentityCard(
    Map<String, dynamic>? userData,
    Map<String, dynamic>? sellerData,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    final photo = userData?['photoURL']?.toString();
    final hasPhoto = photo != null && photo.isNotEmpty;
    final name = userData?['displayName'] ?? user?.displayName ?? 'User';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: ink.emerald.withValues(alpha: 0.15),
            backgroundImage: hasPhoto ? NetworkImage(photo) : null,
            child: hasPhoto
                ? null
                : Icon(Icons.person, size: 30, color: ink.emerald),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  user?.email ?? 'No email',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _muted,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                _buildRoleDisplay(userData, sellerData),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Three numbers that say how much this account uses DentPal: orders placed,
  /// what they have spent this year, and how long they have been here.
  Widget _buildStatsCard() {
    return FutureBuilder<_ProfileStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ink.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _statTile(
                  value: stats == null ? null : '${stats.orderCount}',
                  label: 'Orders',
                  loading: loading,
                ),
                _statDivider(),
                _statTile(
                  value: stats == null
                      ? null
                      : CurrencyFormatter.formatWithPeso(stats.spentThisYear),
                  label: 'Spent this year',
                  loading: loading,
                ),
                _statDivider(),
                _statTile(
                  value: stats?.memberSince == null
                      ? '—'
                      : '${stats!.memberSince!.year}',
                  label: 'Member since',
                  loading: loading && stats == null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statTile({
    required String? value,
    required String label,
    required bool loading,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading || value == null)
              const SkeletonShimmer(
                child: SkeletonBox(width: 56, height: 17, radius: 6),
              )
            else
              FittedBox(
                child: Text(
                  value,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontFamily: AppTextStyles.secondaryFont,
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statDivider() =>
      VerticalDivider(width: 1, thickness: 1, color: ink.border);

  /// Three explicit states rather than a switch: "follow my phone" is the right
  /// default and deserves to be visible rather than implied.
  Widget _buildAppearanceCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 19,
            color: ink.text.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Appearance',
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance,
            builder: (context, mode, _) => Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: ink.surfaceHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ink.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _appearanceOption('Auto', ThemeMode.system, mode),
                  _appearanceOption('Light', ThemeMode.light, mode),
                  _appearanceOption('Dark', ThemeMode.dark, mode),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearanceOption(String label, ThemeMode mode, ThemeMode current) {
    final selected = mode == current;

    return GestureDetector(
      onTap: () => ThemeController.instance.setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? ink.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? ink.border : Colors.transparent),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: selected ? ink.text : ink.text.withValues(alpha: 0.5),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(Map<String, dynamic>? userData) {
    final isBuyer = userData?['role'] == 'buyer';

    final rows = <Widget>[
      // Chats option - hidden when hideChats is true (e.g., in SellerDashboardPage)
      if (!widget.hideChats)
        _menuRow(
          icon: Icons.chat_bubble_outline,
          label: 'Chats',
          detail: 'Your conversations with sellers',
          onTap: () => Navigator.of(context).pushNamed('/profile/chats'),
        ),
      if (isBuyer)
        _menuRow(
          icon: Icons.location_on_outlined,
          label: 'Shipping addresses',
          detail: 'Where your orders are delivered',
          onTap: () => Navigator.of(context).pushNamed('/profile/address'),
        ),
      // Shown for main accounts and sub accounts with permission
      if (SubAccountSessionManager.canManageSubAccounts)
        _menuRow(
          icon: Icons.people_outline,
          label: 'Assistants',
          detail: 'Staff who can order for this clinic',
          onTap: () => Navigator.of(context).pushNamed('/profile/sub-accounts'),
        ),
      _menuRow(
        icon: Icons.star_outline,
        label: 'Reward points',
        detail: 'What you have earned so far',
        onTap: () => Navigator.of(
          context,
        ).pushNamed('/profile/rewards', arguments: userData),
      ),
    ];

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

  Widget _buildSignOutButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _showSignOutConfirmation,
        icon: const Icon(Icons.logout, size: 18),
        label: Text('Sign out', style: AppTextStyles.buttonMedium),
        style: OutlinedButton.styleFrom(
          foregroundColor: _danger,
          side: BorderSide(color: _danger.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  /// What this account is: a buyer with points, or a seller and whether their
  /// store is live.
  Widget _buildRoleDisplay(
    Map<String, dynamic>? userData,
    Map<String, dynamic>? sellerData,
  ) {
    final role = userData?['role'] ?? 'buyer';

    if (role == 'buyer') {
      final rewardPoints = userData?['rewardPoints'] ?? 0;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _badge(
            label: 'Buyer',
            icon: Icons.shopping_cart_outlined,
            tone: ink.emerald,
          ),
          _badge(
            label: '$rewardPoints points',
            icon: Icons.star_outline,
            tone: ink.amber,
          ),
        ],
      );
    }

    if (role == 'seller') {
      final isActive = sellerData?['isActive'] ?? false;
      final activeStatus = isActive is bool
          ? isActive
          : (isActive.toString().toLowerCase() == 'true');

      return _badge(
        label: activeStatus ? 'Active seller' : 'Inactive seller',
        icon: activeStatus
            ? Icons.storefront_outlined
            : Icons.store_mall_directory_outlined,
        tone: activeStatus ? ink.emerald : _danger,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _badge({
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    try {
      // Drop every cached read before signing out, so the next account never
      // sees the previous one's data. SessionCache also does this off the auth
      // stream; doing it here too means the caches are already empty by the
      // time any widget rebuilds.
      SessionCache.clearAll();
      clearCache();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error signing out: $e'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _showSignOutConfirmation() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout, color: _danger),
            const SizedBox(width: 8),
            Text('Sign out', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Sign out', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );

    if (shouldSignOut == true && mounted) {
      await _signOut();
    }
  }
}

/// What the stats row shows. Null figures mean the order read failed — the row
/// keeps its shape and shows what it does know rather than vanishing.
class _ProfileStats {
  const _ProfileStats({
    this.orderCount = 0,
    this.spentThisYear = 0,
    this.memberSince,
  });

  final int orderCount;
  final double spentThisYear;
  final DateTime? memberSince;
}

/// The profile header's bell, with its unread count.
///
/// The bell was drawn here as a bare icon, so the one surface that says "you
/// are signed in as…" was also the one that never said anything had arrived —
/// the same inbox showed a count on Home and on the side rail, but not here.
///
/// A [ValueListenableBuilder] rather than a listener on the page state: the
/// count moves on its own schedule and rebuilding the whole profile — identity
/// card, stats, menu — for a badge tick would be wasteful. It reads the single
/// subscription [NavBadgeService] holds for the session, the same one Home and
/// the rail read, so the three can never disagree.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return ValueListenableBuilder<int>(
      valueListenable: NavBadgeService.instance.unreadNotifications,
      builder: (context, unread, child) {
        if (unread <= 0) return child!;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ink.amber,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: TextStyle(
                    color: ink.onAmber,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      // The icon is passed as `child` so it is built once rather than on every
      // tick; only the badge above it is rebuilt.
      child: Icon(Icons.notifications_outlined, color: ink.text),
    );
  }
}
