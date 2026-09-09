import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/data/services/node_api_service.dart';

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Real-time background sync for smart contract orders every 3 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        context.read<WalletViewModel>().refreshOrdersSilently();
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _openCreateOrderDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateOrderSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final myAccount = vm.currentAccountId;
    final allOrders = vm.orders;
    final openOrders = allOrders.where((o) => o.status == 'OPEN').toList();
    final myOrders = allOrders.where((o) => o.maker == myAccount).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: Text(
          'P2P Smart Contracts',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Auto-Sync 3s',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Orders',
            onPressed: vm.refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.brandPurple,
          indicatorWeight: 3,
          labelColor: AppColors.brandPurple,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: [
            Tab(text: 'Market Orders (${openOrders.length})'),
            Tab(text: 'My Contracts (${myOrders.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrderDialog(context),
        backgroundColor: AppColors.brandPurple,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'New Contract',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _OrderListView(
              orders: openOrders,
              isMarket: true,
              currentAccount: myAccount,
            ),
            _OrderListView(
              orders: myOrders,
              isMarket: false,
              currentAccount: myAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderListView extends StatelessWidget {
  const _OrderListView({
    required this.orders,
    required this.isMarket,
    required this.currentAccount,
  });

  final List<Order> orders;
  final bool isMarket;
  final String? currentAccount;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMarket ? Icons.storefront_outlined : Icons.assignment_outlined,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              isMarket ? 'No open contracts on the market' : 'You have no active contracts',
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderCard(
          order: order,
          isMine: order.maker == currentAccount,
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.isMine});

  final Order order;
  final bool isMine;

  void _showFillSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FillOrderSheet(order: order),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Contract', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to cancel order #${order.id.substring(0, 8)}? Escrowed ${order.offerAmount} ${order.offerToken} will be refunded.',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: GoogleFonts.outfit(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final vm = context.read<WalletViewModel>();
              final err = await vm.cancelOrder(order.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err == null ? 'Order cancelled successfully' : 'Error: $err'),
                    backgroundColor: err == null ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            child: Text('Cancel Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rate = order.offerAmount > 0
        ? (order.requestAmount / order.offerAmount).toStringAsFixed(4)
        : '0.0';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: ID + Status + Partial Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '#${order.id.length > 8 ? order.id.substring(0, 8) : order.id}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandTeal,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: order.status == 'OPEN'
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.status,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: order.status == 'OPEN' ? AppColors.success : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: order.allowPartial
                        ? AppColors.brandPurple.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.allowPartial ? 'Partial Conducting' : 'Exact Amount Only',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: order.allowPartial ? AppColors.brandViolet : Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: context.read<WalletViewModel>().getNickname(order.maker),
              builder: (context, snapshot) {
                final nick = snapshot.data;
                final display = nick != null ? '$nick (@${order.maker})' : '@${order.maker}';
                return Row(
                  children: [
                    const Icon(Icons.person_outline_rounded,
                        size: 13, color: AppColors.brandTeal),
                    const SizedBox(width: 4),
                    Text(
                      'Maker: $display',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),

            // Token Exchange Visual: Offer -> Request
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offers',
                        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            order.offerAmount.toStringAsFixed(2),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          TokenChip(token: order.offerToken, fontSize: 10),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Wants',
                        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            order.requestAmount.toStringAsFixed(2),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          TokenChip(token: order.requestToken, fontSize: 10),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: AppColors.glassStroke, height: 1),
            const SizedBox(height: 10),

            // Footer info: Rate & Maker & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Rate: 1 ${order.offerToken} = $rate ${order.requestToken}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (order.status == 'OPEN') ...[
                  if (isMine)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () => _confirmCancel(context),
                      child: Text('Cancel', style: GoogleFonts.outfit(fontSize: 12)),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () => _showFillSheet(context),
                      child: Text(
                        order.allowPartial ? 'Fill / Trade' : 'Fill Exact',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateOrderSheet extends StatefulWidget {
  const _CreateOrderSheet();

  @override
  State<_CreateOrderSheet> createState() => _CreateOrderSheetState();
}

class _CreateOrderSheetState extends State<_CreateOrderSheet> {
  final _offerAmtCtrl = TextEditingController();
  final _requestAmtCtrl = TextEditingController();
  String _offerToken = 'CSP';
  String _requestToken = 'BDP';
  bool _allowPartial = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _offerAmtCtrl.dispose();
    _requestAmtCtrl.dispose();
    super.dispose();
  }

  void _flipTokens() {
    setState(() {
      final tmp = _offerToken;
      _offerToken = _requestToken;
      _requestToken = tmp;
    });
  }

  void _reviewAndCreate(double depositBalance) {
    final offerAmt = double.tryParse(_offerAmtCtrl.text);
    final reqAmt = double.tryParse(_requestAmtCtrl.text);

    if (offerAmt == null || offerAmt <= 0) {
      setState(() => _error = 'Enter valid offer amount');
      return;
    }
    if (reqAmt == null || reqAmt <= 0) {
      setState(() => _error = 'Enter valid requested amount');
      return;
    }
    if (offerAmt > depositBalance) {
      setState(() => _error = 'Insufficient $_offerToken balance ($depositBalance available)');
      return;
    }

    setState(() => _error = null);
    _showConfirmCreateSheet(depositBalance, offerAmt, reqAmt);
  }

  void _showConfirmCreateSheet(double depositBalance, double offerAmt, double reqAmt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Confirm Smart Contract Creation',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brandPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.brandPurple.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      _ExchangeDetailRow(
                        label: 'Depositing into Escrow',
                        value: '${offerAmt.toStringAsFixed(2)} $_offerToken',
                        highlight: true,
                      ),
                      _ExchangeDetailRow(
                        label: 'Your Current $_offerToken Balance',
                        value: '${depositBalance.toStringAsFixed(2)} $_offerToken',
                      ),
                      _ExchangeDetailRow(
                        label: 'You Request in Return',
                        value: '${reqAmt.toStringAsFixed(2)} $_requestToken',
                      ),
                      _ExchangeDetailRow(
                        label: 'Conduction Policy',
                        value: _allowPartial ? 'Partial Conducting Allowed' : 'Exact Amount Only',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Funds are held securely by the smart contract until fulfilled by peers or cancelled by you.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Confirm & Deposit to Escrow',
                  icon: Icons.lock_outline_rounded,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeCreate(offerAmt, reqAmt);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executeCreate(double offerAmt, double reqAmt) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final vm = context.read<WalletViewModel>();
    final err = await vm.createOrder(
      offerToken: _offerToken,
      offerAmount: offerAmt,
      requestToken: _requestToken,
      requestAmount: reqAmt,
      allowPartial: _allowPartial,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Smart contract order placed in escrow!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Create P2P Contract',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Available balance of deposit token
          Builder(
            builder: (ctx) {
              final vm = ctx.watch<WalletViewModel>();
              final depositBalance = _offerToken == 'CSP'
                  ? (vm.account?.balances.csp ?? 0.0)
                  : (vm.account?.balances.bdp ?? 0.0);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassStroke),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 14,
                          color: _offerToken == 'CSP' ? AppColors.cspColor : AppColors.bdpColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Available Balance:',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          '${depositBalance.toStringAsFixed(2)} $_offerToken',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _offerToken == 'CSP' ? AppColors.cspColor : AppColors.bdpColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            if (depositBalance > 0) {
                              _offerAmtCtrl.text = depositBalance.toStringAsFixed(2);
                              setState(() {});
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'MAX',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandTeal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // Offer Section
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _offerAmtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.outfit(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'You Deposit / Offer',
                    hintText: '0.00',
                    suffixText: _offerToken,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.brandTeal),
                tooltip: 'Swap Tokens',
                onPressed: _flipTokens,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _requestAmtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.outfit(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'You Want / Receive',
                    hintText: '0.00',
                    suffixText: _requestToken,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Partial Conducting Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Allow Partial Conducting',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Others can fill portions of this contract',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _allowPartial,
                  activeThumbColor: AppColors.brandTeal, activeTrackColor: AppColors.brandTeal.withValues(alpha: 0.3),
                  onChanged: (v) => setState(() => _allowPartial = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: GoogleFonts.outfit(color: AppColors.error, fontSize: 13),
              ),
            ),

          Builder(
            builder: (ctx) {
              final vm = ctx.watch<WalletViewModel>();
              final depositBalance = _offerToken == 'CSP'
                  ? (vm.account?.balances.csp ?? 0.0)
                  : (vm.account?.balances.bdp ?? 0.0);
              return GradientButton(
                label: 'Deposit & Create Contract',
                isLoading: _submitting,
                onPressed: () => _reviewAndCreate(depositBalance),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FillOrderSheet extends StatefulWidget {
  const _FillOrderSheet({required this.order});
  final Order order;

  @override
  State<_FillOrderSheet> createState() => _FillOrderSheetState();
}

class _FillOrderSheetState extends State<_FillOrderSheet> {
  final _amountCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _makerNickname;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.order.offerAmount.toString();
    _fetchMakerNickname();
  }

  void _fetchMakerNickname() async {
    final vm = context.read<WalletViewModel>();
    final nick = await vm.getNickname(widget.order.maker);
    if (mounted) {
      setState(() => _makerNickname = nick);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _fillAmt => double.tryParse(_amountCtrl.text) ?? 0.0;

  double get _costToPay {
    if (widget.order.offerAmount <= 0) return 0.0;
    return (_fillAmt / widget.order.offerAmount) * widget.order.requestAmount;
  }

  void _reviewAndConduct(double currentBalance) async {
    if (_fillAmt <= 0 || _fillAmt > widget.order.offerAmount) {
      setState(() => _error = 'Enter amount between 0 and ${widget.order.offerAmount}');
      return;
    }
    if (_costToPay > currentBalance) {
      setState(() => _error = 'Insufficient balance in ${widget.order.requestToken} ($currentBalance available)');
      return;
    }

    if (_makerNickname == null) {
      final vm = context.read<WalletViewModel>();
      final nick = await vm.getNickname(widget.order.maker);
      if (mounted) {
        setState(() => _makerNickname = nick);
      }
    }
    if (!mounted) return;

    _showConductionConfirmSheet(currentBalance);
  }

  void _showConductionConfirmSheet(double currentBalance) {
    final payingToken = widget.order.requestToken;
    final receivingToken = widget.order.offerToken;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Confirm Contract Conduction',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                // Prominent Maker Nickname & Username Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brandTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.brandTeal.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.brandGradient,
                        ),
                        child: Center(
                          child: Text(
                            (_makerNickname != null && _makerNickname!.isNotEmpty)
                                ? _makerNickname![0].toUpperCase()
                                : (widget.order.maker.isNotEmpty
                                    ? widget.order.maker[0].toUpperCase()
                                    : '?'),
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contract Maker (Recipient):',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              _makerNickname != null && _makerNickname!.isNotEmpty
                                  ? _makerNickname!
                                  : '@${widget.order.maker}',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '@${widget.order.maker} (Database Verified)',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: AppColors.brandTeal,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ExchangeDetailRow(
                  label: 'Smart Contract ID',
                  value: '#${widget.order.id.length > 8 ? widget.order.id.substring(0, 8) : widget.order.id}',
                ),
                _ExchangeDetailRow(
                  label: 'Maker Nickname',
                  value: _makerNickname ?? 'Genesis Operator',
                  highlight: _makerNickname != null,
                ),
                _ExchangeDetailRow(
                  label: 'Maker Username',
                  value: '@${widget.order.maker}',
                ),
                _ExchangeDetailRow(
                  label: 'Paying With',
                  value: '$payingToken (Bal: ${currentBalance.toStringAsFixed(2)})',
                ),
                _ExchangeDetailRow(
                  label: 'You Pay to Maker',
                  value: '${_costToPay.toStringAsFixed(4)} $payingToken',
                  highlight: true,
                ),
                _ExchangeDetailRow(
                  label: 'You Receive from Escrow',
                  value: '${_fillAmt.toStringAsFixed(2)} $receivingToken',
                  highlight: true,
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Confirm & Conduct Contract',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _submitting,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeConduction();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executeConduction() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final vm = context.read<WalletViewModel>();
    final isFull = (_fillAmt - widget.order.offerAmount).abs() < 0.00001;
    final err = await vm.fulfillOrder(
      widget.order.id,
      fillAmount: isFull ? null : _fillAmt,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order executed via smart contract!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final payingToken = widget.order.requestToken;
    final currentBalance = payingToken == 'CSP'
        ? (vm.account?.balances.csp ?? 0.0)
        : (vm.account?.balances.bdp ?? 0.0);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Conduct P2P Contract',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),

          // Recipient (Contract Maker) banner with retrieved Nickname
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    color: AppColors.brandTeal, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recipient (Contract Maker):',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _makerNickname != null
                            ? '$_makerNickname (@${widget.order.maker})'
                            : '@${widget.order.maker}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (widget.order.allowPartial) ...[
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Amount of ${widget.order.offerToken} to take',
                suffixText: widget.order.offerToken,
                helperText: 'Max available: ${widget.order.offerAmount} ${widget.order.offerToken}',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'This contract requires full conduction: ${widget.order.offerAmount} ${widget.order.offerToken}',
                style: GoogleFonts.outfit(color: AppColors.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Cost summary and paying coin balance
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Balance in $payingToken:',
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${currentBalance.toStringAsFixed(2)} $payingToken',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: currentBalance >= _costToPay
                            ? AppColors.textPrimary
                            : AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: AppColors.glassStroke, height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'You Pay to Recipient:',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_costToPay.toStringAsFixed(4)} $payingToken',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandTeal,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: GoogleFonts.outfit(color: AppColors.error, fontSize: 13),
              ),
            ),

          GradientButton(
            label: 'Review & Conduct Contract',
            isLoading: _submitting,
            onPressed: () => _reviewAndConduct(currentBalance),
          ),
        ],
      ),
    );
  }
}

class _ExchangeDetailRow extends StatelessWidget {
  const _ExchangeDetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color: highlight ? AppColors.brandTeal : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
