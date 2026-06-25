import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class _TierData {
  final String name;
  final int points;
  final double position;
  final IconData icon;
  final String requirement;
  final String description;
  final List<String> perks;

  const _TierData({
    required this.name,
    required this.points,
    required this.position,
    required this.icon,
    required this.requirement,
    required this.description,
    required this.perks,
  });
}

const _tiers = [
  _TierData(
    name: 'Member',
    points: 0,
    position: 0.0,
    icon: Icons.person_outline,
    requirement: 'Earn and redeem points for unique experiences, stays at over 1,300 locations worldwide and more.',
    description: '',
    perks: [
      'Special member rates',
      'Points for free nights, dining, airline miles, and more',
    ],
  ),
  _TierData(
    name: 'Discoverist',
    points: 25000,
    position: 0.25,
    icon: Icons.explore_outlined,
    requirement: '10 qualifying nights or 25,000 Base Points per calendar year',
    description: 'Enjoy a higher level of service and comfort around the world.',
    perks: [
      '10% points bonus on qualifying spend',
      'Preferred rooms within booked type (availability-based)',
      'Complimentary premium internet',
      'Late checkout (availability-based)',
    ],
  ),
  _TierData(
    name: 'Explorist',
    points: 50000,
    position: 0.50,
    icon: Icons.public_outlined,
    requirement: '30 qualifying nights or 50,000 Base Points per calendar year',
    description: 'Access more comforts, rewards, and upgrades worldwide.',
    perks: [
      '20% points bonus on qualifying spend',
      'Room upgrades (excluding suites/club rooms)',
      'Complimentary premium internet',
      'Late checkout (availability-based)',
    ],
  ),
  _TierData(
    name: 'Globalist',
    points: 100000,
    position: 1.0,
    icon: Icons.language,
    requirement: '60 qualifying nights or 100,000 Base Points per calendar year',
    description: 'Enjoy the highest level of luxury and rewards.',
    perks: [
      '30% points bonus on qualifying spend',
      'Club lounge access + free breakfast',
      'Complimentary premium internet',
      'Late checkout (availability-based)',
    ],
  ),
];

class RewardPointsPage extends StatefulWidget {
  const RewardPointsPage({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  State<RewardPointsPage> createState() => _RewardPointsPageState();
}

class _RewardPointsPageState extends State<RewardPointsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      return 'N/A';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatNumber(dynamic number) {
    final n = number is int ? number : int.tryParse(number.toString()) ?? 0;
    if (n >= 1000) {
      final str = n.toString();
      final buffer = StringBuffer();
      for (var i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
        buffer.write(str[i]);
      }
      return buffer.toString();
    }
    return n.toString();
  }

  void _showTierDialog(_TierData tier, bool isAchieved) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isAchieved
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.grey200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                tier.icon,
                color: isAchieved ? AppColors.primary : AppColors.grey400,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tier.name,
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tier.requirement,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (tier.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tier.description,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Divider(color: AppColors.onSurface.withValues(alpha: 0.1)),
              const SizedBox(height: 12),
              ...tier.perks.map((perk) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        perk,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: AppTextStyles.buttonMedium.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userData = widget.userData;
    final rewardPoints = userData?['rewardPoints'] ?? 0;
    final memberSince = _formatDate(userData?['createdAt']);
    final registrationNo = userData?['RegistrationNo']?.toString() ?? 'N/A';

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
        title: Text(
          'Reward Points',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800;
          final content = Column(
            children: [
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CardDotsPainter(
                          dotColor: AppColors.primary.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                    _buildInfoCard(rewardPoints, memberSince, registrationNo),
                  ],
                ),
              ),
              Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor:
                      AppColors.onSurface.withValues(alpha: 0.6),
                  indicatorColor: AppColors.primary,
                  labelStyle: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: AppTextStyles.labelLarge,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Past Activity'),
                    Tab(text: 'Awards'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(rewardPoints),
                    _buildPastActivityTab(),
                    _buildAwardsTab(),
                  ],
                ),
              ),
            ],
          );

          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Material(
                  color: AppColors.background,
                  child: content,
                ),
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildInfoCard(
    dynamic rewardPoints,
    String memberSince,
    String registrationNo,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.credit_card,
                          size: 16,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'MEMBER',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'DentPal',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Current Point Balance',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatNumber(rewardPoints),
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'pts',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 1,
                color: AppColors.onPrimary.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildCardDetail(
                      label: 'MEMBER SINCE',
                      value: memberSince,
                    ),
                  ),
                  Expanded(
                    child: _buildCardDetail(
                      label: 'REGISTRATION NO',
                      value: registrationNo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardDetail({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(dynamic rewardPoints) {
    final points = rewardPoints is int
        ? rewardPoints
        : int.tryParse(rewardPoints.toString()) ?? 0;
    final qualifyingNights = widget.userData?['qualifyingNights'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Your YTD Progress',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _buildMetricsRow(qualifyingNights, points),
          const SizedBox(height: 24),
          _buildProgressArc(points),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(dynamic nights, int points) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Qualifying Nights',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$nights',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              color: AppColors.onSurface.withValues(alpha: 0.15),
              thickness: 1,
              width: 32,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Qualifying Points',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatNumber(points),
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressArc(int userPoints) {
    final progress = (userPoints / 100000).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const iconSize = 44.0;
          const strokeWidth = 18.0;
          const labelWidth = 90.0;
          const labelHeight = 16.0;
          const bottomLabelGap = 8.0;
          const radialLabelGap = 10.0;
          const topPadding = labelHeight + 6.0;

          final width = constraints.maxWidth;
          final radius = (width - iconSize) / 2;
          final centerX = width / 2;
          final centerY = radius + iconSize / 2 + topPadding;
          final stackHeight =
              centerY + iconSize / 2 + bottomLabelGap + labelHeight + 4;

          return SizedBox(
            width: width,
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: width,
                  height: centerY + strokeWidth / 2,
                  child: CustomPaint(
                    painter: _HalfCircleProgressPainter(
                      progress: progress,
                      trackColor: AppColors.grey200,
                      activeColor: AppColors.primary,
                      strokeWidth: strokeWidth,
                      radius: radius,
                      center: Offset(centerX, centerY),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: centerY - 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatNumber(userPoints),
                        style: TextStyle(
                          fontFamily: AppTextStyles.primaryFont,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'of 100,000',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                ..._tiers.expand((tier) {
                  final angle = math.pi + tier.position * math.pi;
                  final iconX = centerX + radius * math.cos(angle);
                  final iconY = centerY + radius * math.sin(angle);
                  final isAchieved = userPoints >= tier.points;
                  final isEndpoint =
                      tier.position == 0.0 || tier.position == 1.0;

                  double labelCenterX;
                  double labelCenterY;
                  if (isEndpoint) {
                    labelCenterX = iconX;
                    labelCenterY =
                        iconY + iconSize / 2 + bottomLabelGap + labelHeight / 2;
                  } else {
                    final labelDistance =
                        radius + iconSize / 2 + radialLabelGap;
                    labelCenterX = centerX + labelDistance * math.cos(angle);
                    labelCenterY = centerY + labelDistance * math.sin(angle);
                  }

                  return <Widget>[
                    Positioned(
                      left: iconX - iconSize / 2,
                      top: iconY - iconSize / 2,
                      child: GestureDetector(
                        onTap: () => _showTierDialog(tier, isAchieved),
                        child: _buildTierCircle(tier, isAchieved, iconSize),
                      ),
                    ),
                    Positioned(
                      left: labelCenterX - labelWidth / 2,
                      top: labelCenterY - labelHeight / 2,
                      width: labelWidth,
                      child: IgnorePointer(
                        child: Text(
                          tier.name,
                          style: TextStyle(
                            fontFamily: AppTextStyles.primaryFont,
                            fontSize: 11,
                            fontWeight:
                                isAchieved ? FontWeight.w600 : FontWeight.w500,
                            color: isAchieved
                                ? AppColors.primary
                                : AppColors.onSurface.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ];
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTierCircle(_TierData tier, bool isAchieved, double iconSize) {
    return Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: isAchieved ? AppColors.primary : AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: isAchieved ? AppColors.primary : AppColors.grey300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        tier.icon,
        size: 20,
        color: isAchieved ? AppColors.onPrimary : AppColors.grey500,
      ),
    );
  }

  Widget _buildPastActivityTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your reward points activity will appear here',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwardsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No awards yet',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Earn points to unlock exciting awards',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDotsPainter extends CustomPainter {
  final Color dotColor;
  static const double _spacing = 14.0;
  static const double _dotRadius = 1.2;

  _CardDotsPainter({required this.dotColor});

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
  bool shouldRepaint(covariant _CardDotsPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor;
  }
}

class _HalfCircleProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color activeColor;
  final double strokeWidth;
  final double radius;
  final Offset center;

  _HalfCircleProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.activeColor,
    required this.strokeWidth,
    required this.radius,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    if (progress > 0) {
      canvas.drawArc(rect, math.pi, math.pi * progress, false, activePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HalfCircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.radius != radius ||
        oldDelegate.center != center;
  }
}
