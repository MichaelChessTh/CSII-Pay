import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/domain/models/transaction_item.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/ui/features/send/send_screen.dart';
import 'package:csii_pay_app/ui/features/receive/receive_screen.dart';
import 'package:csii_pay_app/ui/features/exchange/exchange_screen.dart';
import 'package:csii_pay_app/ui/features/marketplace/marketplace_screen.dart';
import 'package:csii_pay_app/ui/features/explorer/explorer_screen.dart';
import 'package:csii_pay_app/ui/features/home/widgets/profile_dialog.dart';
import 'package:csii_pay_app/ui/features/groups/groups_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  final _pages = <Widget>[
    const _DashboardPage(),
    const GroupsScreen(),
    const ExchangeScreen(),
    const MarketplaceScreen(),
    const ExplorerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: _pages[_navIndex],
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.glassStroke)),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
          children: [
            _NavItem(
              icon: Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet_rounded,
              label: 'Wallet',
              active: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              icon: Icons.groups_outlined,
              activeIcon: Icons.groups_rounded,
              label: 'Groups',
              active: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            _NavItem(
              icon: Icons.swap_horiz_outlined,
              activeIcon: Icons.swap_horiz_rounded,
              label: 'Exchange',
              active: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              icon: Icons.storefront_outlined,
              activeIcon: Icons.storefront_rounded,
              label: 'Marketplace',
              active: currentIndex == 3,
              onTap: () => onTap(3),
            ),
            _NavItem(
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore_rounded,
              label: 'Explorer',
              active: currentIndex == 4,
              onTap: () => onTap(4),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? activeIcon : icon,
                color: active ? AppColors.brandPurple : AppColors.textMuted,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.brandPurple : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardPage extends StatefulWidget {
  const _DashboardPage();

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletViewModel>().refreshTransactions(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final account = vm.account;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: vm.refresh,
          color: AppColors.brandPurple,
          backgroundColor: AppColors.bgCard,
          child: CustomScrollView(
            slivers: [
              // App Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => ProfileDialog.show(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppColors.brandGradient,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (vm.currentProfile?.nickname.isNotEmpty == true)
                                          ? vm.currentProfile!.nickname[0].toUpperCase()
                                          : (account?.accountId.isNotEmpty == true
                                              ? account!.accountId[0].toUpperCase()
                                              : 'U'),
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Welcome back,',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.info_outline_rounded,
                                            size: 13,
                                            color: AppColors.brandTeal,
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              vm.currentProfile?.nickname.isNotEmpty == true
                                                  ? '${vm.currentProfile!.nickname} (@${account?.accountId ?? ''})'
                                                  : (account?.accountId ?? '—'),
                                              style: GoogleFonts.outfit(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const StatusDot(color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'Live',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () => vm.logout(),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: AppColors.textMuted,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Verification Status Banner & Balance cards
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    children: [
                      if (vm.frozenBdp > 0 || !vm.isVerified)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: vm.isVerified
                                ? AppColors.success.withValues(alpha: 0.12)
                                : Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: vm.isVerified
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: vm.isVerified
                                      ? AppColors.success.withValues(alpha: 0.2)
                                      : Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  vm.isVerified ? Icons.verified_user_rounded : Icons.lock_clock_rounded,
                                  color: vm.isVerified ? AppColors.success : Colors.orangeAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vm.isVerified ? 'Account Verified' : 'Student Verification Pending',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: vm.isVerified ? AppColors.success : Colors.orangeAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      vm.isVerified
                                          ? 'All BDP points unlocked and fully spendable.'
                                          : '${vm.frozenBdp.toStringAsFixed(0)} BDP frozen until Student Council validation.',
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
                      _BalanceCard(
                        label: 'Layer 1 — Base',
                        token: 'CSP',
                        balance: account?.balances.csp ?? 0.0,
                        gradient: AppColors.cspGradient,
                        icon: Icons.hexagon_outlined,
                      ),
                      const SizedBox(height: 12),
                      _BalanceCard(
                        label: 'Layer 2 — Token',
                        token: 'BDP',
                        balance: account?.balances.bdp ?? 0.0,
                        frozenBalance: vm.frozenBdp,
                        gradient: AppColors.bdpGradient,
                        icon: Icons.diamond_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              // Quick Actions
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.arrow_upward_rounded,
                          label: 'Send',
                          gradient: AppColors.bdpGradient,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SendScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scan & Pay',
                          gradient: AppColors.cspGradient,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SendScreen(startWithScanner: true),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.qr_code_rounded,
                          label: 'Receive',
                          gradient: LinearGradient(
                            colors: [
                              AppColors.brandGold,
                              AppColors.brandGold.withValues(alpha: 0.7),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiveScreen(
                                accountId: account?.accountId ?? '',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Network status
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _NetworkCard(vm: vm),
                ),
              ),
              // Transaction History
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Transaction History',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (vm.isLoadingTransactions) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brandPurple,
                              ),
                            ),
                          ],
                        ],
                      ),
                      GestureDetector(
                        onTap: () => vm.refreshTransactions(),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (vm.transactions.isEmpty && vm.isLoadingTransactions)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.brandPurple),
                    ),
                  ),
                )
              else if (vm.transactions.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textMuted),
                          const SizedBox(height: 8),
                          Text(
                            'No transactions yet',
                            style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final tx = vm.transactions[i];
                      return _TransactionTile(tx: tx);
                    },
                    childCount: vm.transactions.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.token,
    required this.balance,
    this.frozenBalance = 0.0,
    required this.gradient,
    required this.icon,
  });

  final String label;
  final String token;
  final double balance;
  final double frozenBalance;
  final LinearGradient gradient;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedBalance(
                  value: balance,
                  symbol: token,
                  textStyle: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                  symbolStyle: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (frozenBalance > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_rounded, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          '${frozenBalance.toStringAsFixed(0)} $token Locked (Pending Verification)',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: gradient.colors.first.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.vm});
  final WalletViewModel vm;

  @override
  Widget build(BuildContext context) {
    final status = vm.nodeStatus;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusDot(color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'Network',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                status?.consensus ?? 'PoA',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppColors.brandTeal,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                label: 'Height',
                value: '#${status?.blockHeight ?? 0}',
              ),
              _StatItem(
                label: 'Peers',
                value: '${status?.peersCount ?? 0}',
              ),
              _StatItem(
                label: 'Mempool',
                value: '${status?.mempoolSize ?? 0}',
              ),
              _StatItem(
                label: 'Active',
                value: '${status?.activeUsersCount ?? 0}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});
  final TransactionItem tx;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final myAccount = vm.currentAccountId ?? '';
    final isIncoming = tx.isIncoming(myAccount);
    final isOutgoing = tx.isOutgoing(myAccount);
    final isPending = tx.status == 'PENDING';
    final fmt = DateFormat('MMM d, HH:mm');

    String title;
    IconData icon;
    Color iconColor;

    if (tx.action == 'POA_REWARD') {
      title = 'PoA Mining Reward';
      icon = Icons.military_tech_rounded;
      iconColor = AppColors.brandGold;
    } else if (tx.action == 'MARKETPLACE_CREATE') {
      title = 'Job Escrow Locked';
      icon = Icons.work_outline_rounded;
      iconColor = const Color(0xFF6366F1);
    } else if (tx.action == 'MARKETPLACE_CLAIM') {
      title = 'Job Payout Claimed';
      icon = Icons.verified_rounded;
      iconColor = AppColors.success;
    } else if (tx.action == 'ORDER_CREATE') {
      title = 'Exchange Escrow';
      icon = Icons.swap_horiz_rounded;
      iconColor = const Color(0xFF3B82F6);
    } else if (tx.action == 'ORDER_FULFILL') {
      title = 'Atomic Swap';
      icon = Icons.swap_horiz_rounded;
      iconColor = AppColors.brandCyan;
    } else if (tx.action == 'ACCOUNT_REGISTER') {
      title = 'Account Welcome Bonus';
      icon = Icons.card_giftcard_rounded;
      iconColor = AppColors.brandPurple;
    } else if (isIncoming) {
      title = 'Received from @${tx.sender}';
      icon = Icons.south_west_rounded;
      iconColor = AppColors.success;
    } else {
      title = 'Sent to @${tx.recipient ?? "recipient"}';
      icon = Icons.north_east_rounded;
      iconColor = AppColors.brandCyan;
    }

    final sign = isIncoming ? '+' : (isOutgoing ? '-' : '');
    final amountColor = isIncoming
        ? AppColors.success
        : (isOutgoing ? Colors.white : AppColors.textPrimary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: InkWell(
          onTap: () => _showTxDetails(context, tx),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isPending ? AppColors.brandGold : AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isPending ? 'Pending' : (tx.blockIndex != null ? 'Block #${tx.blockIndex}' : 'Confirmed'),
                            style: GoogleFonts.outfit(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${fmt.format(tx.dateTime)}',
                          style: GoogleFonts.outfit(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${tx.amount.toStringAsFixed(tx.amount.truncateToDouble() == tx.amount ? 0 : 2)} ${tx.token}',
                    style: GoogleFonts.outfit(
                      color: amountColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (tx.fee > 0)
                    Text(
                      'Fee: ${tx.fee} ${tx.feeToken}',
                      style: GoogleFonts.outfit(
                        color: AppColors.textMuted,
                        fontSize: 10,
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

  void _showTxDetails(BuildContext context, TransactionItem tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Transaction Details',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (tx.status == 'CONFIRMED' ? AppColors.success : AppColors.brandGold)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tx.status,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tx.status == 'CONFIRMED' ? AppColors.success : AppColors.brandGold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Action', tx.action),
            _detailRow('Amount', '${tx.amount} ${tx.token}'),
            if (tx.fee > 0) _detailRow('Network Fee', '${tx.fee} ${tx.feeToken}'),
            _detailRow('Sender', tx.sender),
            if (tx.recipient != null) _detailRow('Recipient', tx.recipient!),
            if (tx.blockIndex != null) _detailRow('Block Height', '#${tx.blockIndex}'),
            _detailRow('Date & Time', tx.dateTime.toLocal().toString()),
            const SizedBox(height: 12),
            Text('Transaction Hash:', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassStroke),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tx.txId,
                      style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.brandCyan),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textSecondary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tx.txId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Transaction ID copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
