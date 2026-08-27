import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/services/sub_account_service.dart';
import '../../core/widgets/app_page_header.dart';
import '../../utils/app_logger.dart';

/// One rung of the loyalty ladder.
class _TierData {
  const _TierData({
    required this.name,
    required this.points,
    required this.icon,
    required this.tagline,
    required this.perks,
  });

  final String name;

  /// Lifetime points that unlock the tier.
  final int points;
  final IconData icon;

  /// One line on what the tier is for.
  final String tagline;
  final List<String> perks;
}

const _tiers = [
  _TierData(
    name: 'Member',
    points: 0,
    icon: Icons.card_membership_outlined,
    tagline: 'Where every DentPal account starts.',
    perks: [
      'Member pricing on selected supplies',
      'Earn points on every completed order',
      'Redeem points against future orders',
    ],
  ),
  _TierData(
    name: 'Silver',
    points: 25000,
    icon: Icons.workspace_premium_outlined,
    tagline: 'For clinics that restock with us regularly.',
    perks: [
      '10% bonus points on every order',
      'Early access to seasonal deals',
      'Priority replies from seller support',
    ],
  ),
  _TierData(
    name: 'Gold',
    points: 50000,
    icon: Icons.military_tech_outlined,
    tagline: 'More value back on the orders you already place.',
    perks: [
      '20% bonus points on every order',
      'Free standard shipping on qualifying orders',
      'Priority replies from seller support',
    ],
  ),
  _TierData(
    name: 'Platinum',
    points: 100000,
    icon: Icons.diamond_outlined,
    tagline: 'The top of the programme.',
    perks: [
      '30% bonus points on every order',
      'Free express shipping on qualifying orders',
      'A dedicated account manager',
      'Invitations to DentPal partner events',
    ],
  ),
];

/// Points balance, tier progress, and what each tier is worth.
///
/// Was an `AppBar` + Material `TabBar` on hardcoded light surfaces, with the
/// tiers laid out around a half-circle gauge whose labels were positioned by
/// trigonometry and collided on narrow phones. It now wears the marketplace
/// frame — [AppPageHeader], the gutter, filter pills, [InkPalette] — so it
/// matches Profile, Orders and Settings in both themes, and the gauge is the
/// same left-to-right rail the order tracker uses.
class RewardPointsPage extends StatefulWidget {
  const RewardPointsPage({super.key, this.userData});

  /// The buyer's User document. Profile already has it and hands it over, so
  /// the balance is right on the first frame; a cold load of
  /// '/profile/rewards' has none and the page reads it itself.
  final Map<String, dynamic>? userData;

  @override
  State<RewardPointsPage> createState() => _RewardPointsPageState();
}

class _RewardPointsPageState extends State<RewardPointsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabLabels = ['Overview', 'Activity', 'Rewards'];

  Map<String, dynamic>? _userData;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this)
      // Swiping the view has to move the pills too, so they stay the one
      // indicator of which tab you are on.
      ..addListener(_onTabChanged);

    _userData = widget.userData;
    if (_userData == null) _loadUserData();
  }

  /// The cold-load path: opened at '/profile/rewards' rather than pushed from
  /// Profile, so there is no document in hand. Sub accounts read the clinic's,
  /// the same one every other profile surface shows them.
  Future<void> _loadUserData() async {
    setState(() => _loading = true);
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        final doc = await FirebaseFirestore.instance
            .collection('User')
            .doc(SubAccountSessionManager.getEffectiveUserId())
            .get();
        if (doc.exists) _userData = doc.data();
      }
    } catch (e) {
      AppLogger.d('Error loading reward points: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  // ── Data ─────────────────────────────────────────────────────────────────

  int get _points {
    final raw = _userData?['rewardPoints'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Highest tier the balance has reached.
  _TierData get _currentTier =>
      _tiers.lastWhere((t) => _points >= t.points, orElse: () => _tiers.first);

  /// The rung above [_currentTier], or null at the top of the ladder.
  _TierData? get _nextTier {
    final index = _tiers.indexOf(_currentTier);
    return index >= _tiers.length - 1 ? null : _tiers[index + 1];
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp is! Timestamp) return 'N/A';
    final date = timestamp.toDate();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatNumber(int n) {
    final str = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(color: ink.emerald),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildActivityTab(),
                            _buildRewardsTab(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return AppPageHeader(
      title: 'Reward points',
      // Same shape as every other page: the screen's name, then one line of
      // state under it. Held back until the balance is known, so it never
      // flashes "0 points · Member" at a buyer who has plenty.
      subtitle: _loading
          ? null
          : '${_formatNumber(_points)} points · ${_currentTier.name}',
      bottom: _buildTabPills(),
    );
  }

  Widget _buildTabPills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _tabLabels.length; i++) ...[
            _buildPill(
              label: _tabLabels[i],
              selected: _tabController.index == i,
              onTap: () => _tabController.animateTo(i),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? ink.emerald : ink.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? ink.emerald : ink.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: selected ? ink.onEmerald : ink.text.withValues(alpha: 0.8),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  // ── Overview ─────────────────────────────────────────────────────────────

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    28,
  );

  Widget _buildOverviewTab() {
    return ListView(
      padding: _listPadding,
      children: [
        _buildMembershipCard(),
        const SizedBox(height: 24),
        _buildSectionHeader('Your progress'),
        const SizedBox(height: 12),
        _buildProgressCard(),
        const SizedBox(height: 24),
        _buildSectionHeader('Tiers'),
        const SizedBox(height: 12),
        _buildTiersCard(),
        const SizedBox(height: 24),
        _buildSectionHeader('How points work'),
        const SizedBox(height: 12),
        _buildHowItWorksCard(),
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

  /// The balance, as a membership card in the hero's emerald.
  Widget _buildMembershipCard() {
    final memberSince = _formatDate(_userData?['createdAt']);
    final registrationNo = _userData?['RegistrationNo']?.toString() ?? 'N/A';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: InkPalette.heroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Faint dot field, so the card reads as a printed membership card
          // rather than a flat block of green.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CardDotsPainter(
                  dotColor: Colors.white.withValues(alpha: 0.09),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'DENTPAL',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    _buildTierBadge(),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Points balance',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatNumber(_points),
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 34,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'pts',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildCardDetail('Member since', memberSince),
                    ),
                    Expanded(
                      child: _buildCardDetail('Member ID', registrationNo),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_currentTier.icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            _currentTier.name,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Where the balance sits on the ladder, and what is left to the next rung.
  Widget _buildProgressCard() {
    final next = _nextTier;
    final remaining = next == null ? 0 : next.points - _points;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  next == null
                      ? 'Top tier reached'
                      : '${_formatNumber(remaining)} points to ${next.name}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _currentTier.name,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            next == null
                ? 'You are getting the most the programme offers.'
                : 'Keep ordering to unlock ${next.name} benefits.',
            style: AppTextStyles.bodySmall.copyWith(
              color: _muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildTierRail(),
        ],
      ),
    );
  }

  /// The four tiers as stops on one track, in the same shape as the order
  /// tracker's rail. Replaces the half-circle gauge, whose labels were placed
  /// by angle and overlapped on narrow screens.
  Widget _buildTierRail() {
    const nodeSize = 34.0;
    const trackHeight = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final span = width - nodeSize;
        final step = span / (_tiers.length - 1);
        // Filled length: whole segments already cleared, plus the fraction of
        // the segment the balance is part-way through.
        final index = _tiers.indexOf(_currentTier);
        final next = _nextTier;
        final fraction = next == null
            ? 0.0
            : ((_points - _currentTier.points) /
                      (next.points - _currentTier.points))
                  .clamp(0.0, 1.0);
        final filled = (index + fraction) * step;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: nodeSize,
              child: Stack(
                children: [
                  Positioned(
                    left: nodeSize / 2,
                    right: nodeSize / 2,
                    top: (nodeSize - trackHeight) / 2,
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: ink.surfaceHigh,
                        borderRadius: BorderRadius.circular(trackHeight),
                      ),
                    ),
                  ),
                  Positioned(
                    left: nodeSize / 2,
                    top: (nodeSize - trackHeight) / 2,
                    child: Container(
                      width: filled.clamp(0.0, span),
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: ink.emerald,
                        borderRadius: BorderRadius.circular(trackHeight),
                      ),
                    ),
                  ),
                  for (var i = 0; i < _tiers.length; i++)
                    Positioned(
                      left: i * step,
                      top: 0,
                      child: _buildRailNode(
                        _tiers[i],
                        reached: _points >= _tiers[i].points,
                        current: i == index,
                        size: nodeSize,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: width,
              child: Stack(
                children: [
                  // Labels are centred under their node, then clamped to the
                  // card so the first and last never hang off the edge.
                  for (var i = 0; i < _tiers.length; i++)
                    Positioned(
                      left: (i * step + nodeSize / 2 - 40).clamp(
                        0.0,
                        // Never negative: a card narrower than one label would
                        // otherwise make the upper bound the smaller of the two.
                        width > 80 ? width - 80 : 0.0,
                      ),
                      width: 80,
                      child: Text(
                        _tiers[i].name,
                        textAlign: i == 0
                            ? TextAlign.left
                            : i == _tiers.length - 1
                            ? TextAlign.right
                            : TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _points >= _tiers[i].points
                              ? ink.emerald
                              : ink.text.withValues(alpha: 0.45),
                          fontWeight: _points >= _tiers[i].points
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  // Reserves the row's height; the labels above are positioned.
                  Opacity(
                    opacity: 0,
                    child: Text(
                      _tiers.first.name,
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRailNode(
    _TierData tier, {
    required bool reached,
    required bool current,
    required double size,
  }) {
    return GestureDetector(
      onTap: () => _showTierSheet(tier),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: reached ? ink.emerald : ink.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: reached ? ink.emerald : ink.border,
            width: 2,
          ),
          // Only the tier you are standing on gets a halo.
          boxShadow: current
              ? [
                  BoxShadow(
                    color: ink.emerald.withValues(alpha: 0.28),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(
          tier.icon,
          size: 16,
          color: reached ? ink.onEmerald : ink.text.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  /// The ladder as a menu card, in the row shape Profile and Settings use.
  Widget _buildTiersCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _tiers.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Divider(height: 1, color: ink.border),
              ),
            _buildTierRow(_tiers[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTierRow(_TierData tier) {
    final reached = _points >= tier.points;
    final isCurrent = tier == _currentTier;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTierSheet(tier),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: reached
                      ? ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11)
                      : ink.surfaceHigh,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  tier.icon,
                  size: 19,
                  color: reached
                      ? ink.emerald
                      : ink.text.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tier.name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: ink.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ink.emerald.withValues(
                                alpha: ink.isDark ? 0.16 : 0.11,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'You',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: ink.emerald,
                                fontWeight: FontWeight.w700,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tier.points == 0
                          ? 'Included with every account'
                          : '${_formatNumber(tier.points)} points'
                                '${reached ? ' · unlocked' : ''}',
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

  Widget _buildHowItWorksCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.shopping_bag_outlined,
            label: 'Earn as you order',
            detail: 'Completed orders add points to your balance.',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Divider(height: 1, color: ink.border),
          ),
          _buildInfoRow(
            icon: Icons.redeem_outlined,
            label: 'Spend them at checkout',
            detail: 'Put your balance towards a future order.',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Divider(height: 1, color: ink.border),
          ),
          _buildInfoRow(
            icon: Icons.trending_up,
            label: 'Climb the tiers',
            detail: 'Higher tiers earn points faster and unlock more perks.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
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
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tier detail ──────────────────────────────────────────────────────────

  /// What a tier is worth, in the marketplace sheet shape. Was an `AlertDialog`
  /// on a hardcoded light surface.
  void _showTierSheet(_TierData tier) {
    final reached = _points >= tier.points;
    final isCurrent = tier == _currentTier;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ink.border),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink.text.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.gutter,
                  0,
                  AppLayout.gutter,
                  8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: reached
                            ? ink.emerald.withValues(
                                alpha: ink.isDark ? 0.16 : 0.11,
                              )
                            : ink.surfaceHigh,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        tier.icon,
                        size: 22,
                        color: reached
                            ? ink.emerald
                            : ink.text.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.name,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: ink.text,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isCurrent
                                ? 'Your current tier'
                                : reached
                                ? 'Unlocked'
                                : '${_formatNumber(tier.points - _points)} '
                                      'points away',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: reached ? ink.emerald : _muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppLayout.gutter,
                ),
                child: Text(
                  tier.tagline,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _muted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppLayout.gutter,
                ),
                child: Divider(height: 1, color: ink.border),
              ),
              const SizedBox(height: 14),
              for (final perk in tier.perks)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppLayout.gutter,
                    0,
                    AppLayout.gutter,
                    12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 17,
                        color: reached
                            ? ink.emerald
                            : ink.text.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          perk,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: ink.text.withValues(alpha: 0.85),
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ── Activity & rewards ───────────────────────────────────────────────────

  Widget _buildActivityTab() {
    return _buildStateMessage(
      icon: Icons.history,
      title: 'No activity yet',
      detail: 'Points you earn and spend will show up here, newest first.',
    );
  }

  Widget _buildRewardsTab() {
    return _buildStateMessage(
      icon: Icons.card_giftcard_outlined,
      title: 'No rewards yet',
      detail: 'Rewards you can claim with your points will appear here.',
    );
  }

  /// The empty state every buyer surface wears.
  Widget _buildStateMessage({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: ink.emerald.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: ink.emerald),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dot field behind the membership card.
class _CardDotsPainter extends CustomPainter {
  _CardDotsPainter({required this.dotColor});

  final Color dotColor;

  static const double _spacing = 14.0;
  static const double _dotRadius = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (double y = _spacing / 2; y < size.height; y += _spacing) {
      for (double x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CardDotsPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor;
}
