import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/services/node_api_service.dart';
import '../../core/theme.dart';
import '../home/view_models/wallet_view_model.dart';

class ActivityScoreScreen extends StatefulWidget {
  const ActivityScoreScreen({super.key});

  @override
  State<ActivityScoreScreen> createState() => _ActivityScoreScreenState();
}

class _ActivityScoreScreenState extends State<ActivityScoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletViewModel>().fetchActivityData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletViewModel>(
      builder: (context, vm, _) {
        final activityData = vm.activityData;
        final myScore = vm.userActivityScore;
        final myRank = vm.userActivityRank;
        final myEntry = vm.userActivityEntry;
        final status = vm.nodeStatus;
        final blocksLeft = status?.blocksUntilLottery ??
            activityData?.blocksUntilLottery ??
            10;
        final nextLottery =
            status?.nextLotteryBlock ?? activityData?.nextLotteryBlock ?? 10;

        return Scaffold(
          backgroundColor: AppColors.bgDeep,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity Hub & Rewards',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'PoA Activity Score & 10th Block Lottery',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.brandTeal),
                tooltip: 'Refresh Activity Data',
                onPressed: () => vm.fetchActivityData(),
              ),
            ],
          ),
          body: Column(
            children: [
              // Hero Summary Card
              _buildHeroCard(myScore, myRank, myEntry, blocksLeft, nextLottery,
                  activityData),
              const SizedBox(height: 12),
              // Tab Bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassStroke),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: AppColors.brandGradient,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: GoogleFonts.outfit(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
                  tabs: const [
                    Tab(text: 'My Breakdown'),
                    Tab(text: 'How It Works'),
                    Tab(text: 'Leaderboard'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMyBreakdownTab(myEntry, myScore),
                    _buildHowItWorksTab(),
                    _buildLeaderboardTab(activityData, vm.currentAccountId),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroCard(
    double score,
    int rank,
    StudentLeaderboardEntry? entry,
    int blocksLeft,
    int nextLottery,
    ActivityLeaderboardResponse? activityData,
  ) {
    final winProb = entry?.winProbabilityPct ?? 0.0;
    final tickets = entry?.tickets ?? (1.0 + score);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.basciiGold.withValues(alpha: 0.25),
            AppColors.bgCard,
            AppColors.basciiGoldDark.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.basciiGold.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.basciiGold.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR ACTIVITY SCORE',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: AppColors.basciiGoldBright,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        score.toStringAsFixed(1),
                        style: GoogleFonts.outfit(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'PTS',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.basciiGoldBright,
                        ),
                      ),
                    ],
                  ),
                  if (entry?.tier != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.basciiGold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.basciiGold.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        entry!.tier!.badge,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.basciiGoldLight,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Rank Pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: rank == 1
                      ? AppColors.brandGold.withValues(alpha: 0.2)
                      : (rank <= 3
                          ? AppColors.brandTeal.withValues(alpha: 0.2)
                          : AppColors.glassFill),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: rank == 1
                        ? AppColors.brandGold
                        : (rank <= 3
                            ? AppColors.brandTeal
                            : AppColors.glassStroke),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      rank > 0 ? '#$rank' : 'Unranked',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: rank == 1
                            ? AppColors.brandGold
                            : (rank <= 3
                                ? AppColors.brandTeal
                                : AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      'Campus Rank',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry?.tier != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgDeep.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassStroke),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Prestige Tier Progress',
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                      Text(
                        entry!.tier!.nextTier != null
                            ? '${entry.tier!.pointsToNext.toStringAsFixed(1)} pts to ${entry.tier!.nextTier}'
                            : 'Highest Prestige Tier',
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.basciiGoldBright),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (entry.tier!.progressPct / 100.0).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.bgDeep,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.basciiGold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // 10th-block Lottery Countdown Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgDeep.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandViolet.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.card_giftcard_rounded,
                      color: AppColors.bdpColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '10th-Block 0.1 BDP Raffle',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Block #$nextLottery (in $blocksLeft)',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandTeal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your tickets: ${tickets.toStringAsFixed(1)} | Win Probability: ${winProb.toStringAsFixed(1)}%',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyBreakdownTab(
      StudentLeaderboardEntry? entry, double totalScore) {
    if (entry == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.query_stats_rounded,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'No Activity Recorded Yet',
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Complete marketplace jobs, make transfers, or pay commissions to earn score points!',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final b = entry.breakdown;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Breakdown intro with BAScii Theme
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.basciiGold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded,
                  size: 20, color: AppColors.basciiGoldBright),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uncapped Continuous Activity Engine',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scores grow without arbitrary ceilings. Higher task difficulties and interdisciplinary diversity earn massive multipliers!',
                      style: GoogleFonts.outfit(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Ecosystem Diversity Multiplier Card
        if (entry.diversity != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.basciiGold.withValues(alpha: 0.2),
                  AppColors.bgCard,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.basciiGold.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hub_rounded,
                            size: 18, color: AppColors.basciiGoldBright),
                        const SizedBox(width: 8),
                        Text(
                          'Ecosystem Diversity Multiplier',
                          style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.basciiGold.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${entry.diversity!.multiplier.toStringAsFixed(2)}x',
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.basciiGoldBright),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Transfers (${entry.diversity!.hasTransfers ? '✓' : '✗'}) • Jobs (${entry.diversity!.hasJobs ? '✓' : '✗'}) • DEX Swaps (${entry.diversity!.hasExchange ? '✓' : '✗'}) • Teams (${entry.diversity!.hasGroup ? '✓' : '✗'})',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Parameter 1: Monthly Activity
        _buildMetricTile(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.basciiGoldBright,
          title: 'Monthly Activity',
          weightText: 'Continuous logarithmic rate',
          valueText: '${b.monthlyActivity.val.toInt()} transactions this month',
          pointsText: '+${b.monthlyActivity.pts.toStringAsFixed(1)} pts',
          progress: (b.monthlyActivity.pts / 100.0).clamp(0.0, 1.0),
          color: AppColors.basciiGoldBright,
        ),
        const SizedBox(height: 10),

        // Parameter 2: Monthly Commissions
        _buildMetricTile(
          icon: Icons.payments_rounded,
          iconColor: AppColors.brandGold,
          title: 'Monthly Commissions Paid',
          weightText: 'CSP fees logarithmic progression',
          valueText:
              '${b.monthlyCommissions.val.toStringAsFixed(4)} CSP paid in fees this month',
          pointsText: '+${b.monthlyCommissions.pts.toStringAsFixed(1)} pts',
          progress: (b.monthlyCommissions.pts / 200.0).clamp(0.0, 1.0),
          color: AppColors.brandGold,
        ),
        const SizedBox(height: 10),

        // Parameter 3: All-Time Activity
        _buildMetricTile(
          icon: Icons.history_rounded,
          iconColor: AppColors.info,
          title: 'All-Time Activity',
          weightText: 'Cumulative transactions scale',
          valueText:
              '${b.allTimeActivity.val.toInt()} transactions since release',
          pointsText: '+${b.allTimeActivity.pts.toStringAsFixed(1)} pts',
          progress: (b.allTimeActivity.pts / 100.0).clamp(0.0, 1.0),
          color: AppColors.info,
        ),
        const SizedBox(height: 10),

        // Parameter 4: All-Time Commissions
        _buildMetricTile(
          icon: Icons.account_balance_wallet_rounded,
          iconColor: AppColors.bdpColor,
          title: 'All-Time Commissions Paid',
          weightText: 'Cumulative CSP fees contribution',
          valueText:
              '${b.allTimeCommissions.val.toStringAsFixed(4)} CSP paid in fees since release',
          pointsText: '+${b.allTimeCommissions.pts.toStringAsFixed(1)} pts',
          progress: (b.allTimeCommissions.pts / 100.0).clamp(0.0, 1.0),
          color: AppColors.bdpColor,
        ),
        const SizedBox(height: 10),

        // Parameter 5: Completed Jobs (Exponential scale)
        _buildMetricTile(
          icon: Icons.stars_rounded,
          iconColor: AppColors.success,
          title: 'Completed Jobs & Tasks (Exponential Weight)',
          weightText: '1★: 10pts, 2★: 25pts, 3★: 50pts, 4★: 100pts, 5★: 200pts',
          valueText:
              '${b.jobsComplexity.jobsCount} marketplace jobs completed (${b.jobsComplexity.val.toInt()} job pts)',
          pointsText: '+${b.jobsComplexity.pts.toStringAsFixed(0)} pts',
          progress: (b.jobsComplexity.pts / 500.0).clamp(0.0, 1.0),
          color: AppColors.success,
        ),
        const SizedBox(height: 16),

        // Total calculation summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppColors.basciiGold.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Activity Score',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (entry.tier != null)
                        Text(
                          entry.tier!.badge,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.basciiGoldBright,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    '${totalScore.toStringAsFixed(1)} PTS',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.basciiGoldBright,
                    ),
                  ),
                ],
              ),
              if (entry.tier != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (entry.tier!.progressPct / 100.0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.bgDeep,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.basciiGold),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.tier!.name,
                      style: GoogleFonts.outfit(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    Text(
                      entry.tier!.nextTier != null
                          ? '${entry.tier!.pointsToNext.toStringAsFixed(1)} pts to ${entry.tier!.nextTier}'
                          : 'Max Prestige',
                      style: GoogleFonts.outfit(
                          fontSize: 11, color: AppColors.basciiGoldLight),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String weightText,
    required String valueText,
    required String pointsText,
    required double progress,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      weightText,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                pointsText,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.bgDeep,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valueText,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Section 1: Why maintain high activity
        _buildSectionHeader('Why Maintain a High Activity Score?'),
        const SizedBox(height: 8),
        _buildBenefitCard(
          icon: Icons.monetization_on_rounded,
          color: AppColors.brandGold,
          title: '0.1 BDP Minted Every 10 Blocks',
          description:
              'On every 10th block (e.g. Block #10, #20, #30), an automated consensus lottery runs. Exactly 0.1 BDP is minted directly into the winning student account!',
        ),
        const SizedBox(height: 8),
        _buildBenefitCard(
          icon: Icons.casino_rounded,
          color: AppColors.brandTeal,
          title: 'Weighted Randomization (Lottery Tickets)',
          description:
              'Your total Activity Score determines your ticket share. A higher score gives you significantly higher winning odds, while random selection ensures every active student always has a chance to win!',
        ),
        const SizedBox(height: 8),
        _buildBenefitCard(
          icon: Icons.workspace_premium_rounded,
          color: AppColors.brandViolet,
          title: 'Student Reputation & Council Trust',
          description:
              'High activity scores grant priority ranking in student marketplace applications, group leadership credibility, and eligibility for Student Council honors.',
        ),
        const SizedBox(height: 18),

        // Section 2: BAScii Prestige Tiers
        _buildSectionHeader('BAScii Prestige Tiers'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppColors.basciiGold.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _buildFormulaRow(
                  '👑 BAScii Fellow', '1,500+ pts', AppColors.basciiGold),
              _buildFormulaRow('💎 Platinum Architect', '700 - 1,499 pts',
                  AppColors.basciiGoldLight),
              _buildFormulaRow('🥇 Gold Trailblazer', '300 - 699 pts',
                  AppColors.basciiGoldBright),
              _buildFormulaRow('🥈 Silver Innovator', '100 - 299 pts',
                  const Color(0xFFA8B2C1)),
              _buildFormulaRow(
                  '🥉 Bronze Scholar', '0 - 99 pts', const Color(0xFFCD7F32)),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Section 3: Exact Formulas & Scaling
        _buildSectionHeader('Continuous Scoring & Multipliers'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Uncapped Logarithmic Progression',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scores grow continuously with diminishing marginal returns. Hard work always moves your rank forward without hitting arbitrary caps.',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
              const Divider(color: AppColors.glassStroke, height: 24),
              Text(
                'Exponential Job Difficulty Scale',
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              _buildFormulaRow(
                  '1★ Microtask', '+10 pts', AppColors.textSecondary),
              _buildFormulaRow(
                  '2★ Collaborative Sprint', '+25 pts', AppColors.info),
              _buildFormulaRow(
                  '3★ Module Deliverable', '+50 pts', AppColors.brandGold),
              _buildFormulaRow(
                  '4★ Milestone Project', '+100 pts', AppColors.brandViolet),
              _buildFormulaRow(
                  '5★ Capstone Innovation', '+200 pts', AppColors.success),
              const Divider(color: AppColors.glassStroke, height: 24),
              Text(
                'Interdisciplinary Diversity Multiplier',
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'True to BAScii\'s integrated innovation mission, students who engage across multiple modules (Transfers + Marketplace Jobs + DEX Swaps + Team Governance) earn up to a +25% composite score multiplier (1.0x to 1.25x)!',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Section 4: Tips to increase score
        _buildSectionHeader('Tips to Boost Your Prestige'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTipRow('1',
                  'Tackle higher-difficulty (3-5★) innovation jobs for exponential score leaps.'),
              const SizedBox(height: 6),
              _buildTipRow('2',
                  'Maintain monthly active streaks by transferring Service Points (CSP) and trading on the DEX.'),
              const SizedBox(height: 6),
              _buildTipRow('3',
                  'Unlock the full 1.25x Diversity Multiplier by joining a student group and creating orders.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildBenefitCard({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassStroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaRow(String label, String percent, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textPrimary),
              ),
            ],
          ),
          Text(
            percent,
            style: GoogleFonts.outfit(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandTeal.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            num,
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.brandTeal),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.outfit(
                fontSize: 12, color: AppColors.textSecondary, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardTab(
      ActivityLeaderboardResponse? data, String? currentUserId) {
    final students = data?.students ?? [];
    final winners = data?.recentLotteryWinners ?? [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Students Leaderboard
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Student Rankings (${students.length} Active)',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Total Tickets: ${data?.totalTickets.toStringAsFixed(0) ?? '0'}',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppColors.brandTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (students.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Text(
              'No active students yet. Be the first to earn points!',
              style: GoogleFonts.outfit(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          ...students.map((s) {
            final isMe = s.accountId == currentUserId;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.brandPurple.withValues(alpha: 0.2)
                    : AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMe
                      ? AppColors.brandPurple
                      : (s.rank <= 3
                          ? AppColors.brandGold.withValues(alpha: 0.4)
                          : AppColors.glassStroke),
                  width: isMe ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  // Rank badge
                  _buildRankBadge(s.rank),
                  const SizedBox(width: 12),
                  // User details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '@${s.accountId}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isMe
                                    ? AppColors.brandTeal
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.brandTeal
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'YOU',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandTeal,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (s.tier != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            s.tier!.badge,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.basciiGoldBright,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          '${s.completedJobsCount} jobs completed • ${s.winProbabilityPct.toStringAsFixed(1)}% lottery chance',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Score
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        s.activityScore.toStringAsFixed(1),
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'pts',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 20),

        // Recent 10th Block Lottery Winners
        Text(
          'Recent 10th-Block Winners (0.1 BDP)',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        if (winners.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Text(
              'No 10th-block lottery rewards have occurred yet. Block #10 will be the first draw!',
              style: GoogleFonts.outfit(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          ...winners.map((w) {
            final dateStr = w.timestamp > 0
                ? DateFormat('HH:mm, dd MMM').format(
                    DateTime.fromMillisecondsSinceEpoch(
                        (w.timestamp * 1000).toInt()))
                : 'Recent';

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassStroke),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bdpColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Block #${w.blockHeight}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.bdpColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '@${w.recipient}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${w.amount} ${w.token}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFFFD700),
          shape: BoxShape.circle,
        ),
        child: const Text('🥇', style: TextStyle(fontSize: 16)),
      );
    } else if (rank == 2) {
      return Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFC0C0C0),
          shape: BoxShape.circle,
        ),
        child: const Text('🥈', style: TextStyle(fontSize: 16)),
      );
    } else if (rank == 3) {
      return Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFCD7F32),
          shape: BoxShape.circle,
        ),
        child: const Text('🥉', style: TextStyle(fontSize: 16)),
      );
    } else {
      return Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Text(
          '#$rank',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
  }
}
