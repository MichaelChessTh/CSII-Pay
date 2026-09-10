import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/data/services/node_api_service.dart';
import 'package:csii_pay_app/domain/models/user_profile.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  final _searchCtrl = TextEditingController();
  bool _isSearchingAccount = false;
  AccountInfo? _inspectedAccount;
  UserProfile? _inspectedProfile;
  String? _accountSearchError;

  bool _showAllBlocks = false;
  String _blockSearchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: AppColors.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _performAccountSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearchingAccount = true;
      _accountSearchError = null;
      _inspectedAccount = null;
      _inspectedProfile = null;
    });

    final vm = context.read<WalletViewModel>();
    try {
      final res = await vm.inspectAccount(query);
      if (res.success && res.data != null) {
        final profile = await vm.getUserProfile(query);
        if (mounted) {
          setState(() {
            _inspectedAccount = res.data;
            _inspectedProfile = profile;
            _isSearchingAccount = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _accountSearchError = res.error ?? 'Account not found';
            _isSearchingAccount = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accountSearchError = 'Error inspecting account: $e';
          _isSearchingAccount = false;
        });
      }
    }
  }

  void _showBlockDetails(BuildContext context, Block block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BlockDetailSheet(block: block),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final node = vm.nodeStatus;
    final allBlocks = vm.allBlocks.isNotEmpty ? vm.allBlocks : vm.recentBlocks;
    final filteredBlocks = allBlocks.where((b) {
      if (_blockSearchQuery.isEmpty) return true;
      final q = _blockSearchQuery.toLowerCase();
      return b.index.toString().contains(q) ||
          b.hash.toLowerCase().contains(q) ||
          b.validator.toLowerCase().contains(q);
    }).toList();

    final displayedBlocks = _showAllBlocks ? filteredBlocks : filteredBlocks.take(10).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: Text(
          'Blockchain Explorer',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: vm.refresh,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: RefreshIndicator(
          onRefresh: vm.refresh,
          color: AppColors.brandPurple,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Account Lookup / Balance Inspector Card
              _buildAccountSearchSection(),
              const SizedBox(height: 20),

              // 2. Network Stats Overview Card
              GlassCard(
                blur: 16,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const StatusDot(color: AppColors.success, size: 10),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'CSII-Pay Network Live',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandPurple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            node?.consensus ?? 'Proof of Activity',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppColors.brandViolet,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _StatItem(
                          label: 'Chain Height',
                          value: '#${node?.blockHeight ?? allBlocks.length}',
                          icon: Icons.layers_rounded,
                        ),
                        _StatItem(
                          label: 'Active Peers',
                          value: '${node?.peersCount ?? 0}',
                          icon: Icons.hub_rounded,
                        ),
                        _StatItem(
                          label: 'Mempool',
                          value: '${node?.mempoolSize ?? 0} tx',
                          icon: Icons.hourglass_top_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: AppColors.glassStroke, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Node Operator: ${node?.operatorAccount ?? "None"}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${node?.activeUsersCount ?? 0} Active Miners',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppColors.brandTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Chain Blocks Header & Review Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _showAllBlocks ? 'All Blocks (${allBlocks.length})' : 'Recent Blocks',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(
                      _showAllBlocks ? Icons.compress_rounded : Icons.expand_rounded,
                      size: 16,
                      color: AppColors.brandCyan,
                    ),
                    label: Text(
                      _showAllBlocks ? 'Show Recent 10' : 'View All Blocks',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandCyan,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _showAllBlocks = !_showAllBlocks);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Block Filter Search Bar
              if (_showAllBlocks) ...[
                TextField(
                  onChanged: (v) => setState(() => _blockSearchQuery = v.trim()),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter blocks by height, validator, or hash...',
                    hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.bgCard,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.glassStroke),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Blocks List
              if (displayedBlocks.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No blocks match your search',
                      style: GoogleFonts.outfit(color: AppColors.textMuted),
                    ),
                  ),
                )
              else
                ...displayedBlocks.map((b) => _BlockCard(
                      block: b,
                      onTap: () => _showBlockDetails(context, b),
                      onCopy: (txt, lbl) => _copy(context, txt, lbl),
                    )),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSearchSection() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search_rounded, color: AppColors.brandCyan, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lookup Account Balance & Identity',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Inspect balances, profile, and mining score of any user on-chain',
            style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter Account ID or Username...',
                    hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.badge_outlined, size: 18, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.bgDeep,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.glassStroke),
                    ),
                  ),
                  onSubmitted: (_) => _performAccountSearch(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSearchingAccount ? null : _performAccountSearch,
                child: _isSearchingAccount
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        'Check',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
              ),
            ],
          ),

          // Error box
          if (_accountSearchError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _accountSearchError!,
                      style: GoogleFonts.outfit(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Inspected Account Result Card
          if (_inspectedAccount != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.brandCyan.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                            (_inspectedProfile?.nickname.isNotEmpty == true)
                                ? _inspectedProfile!.nickname[0].toUpperCase()
                                : _inspectedAccount!.accountId[0].toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontSize: 18,
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
                              _inspectedProfile?.nickname.isNotEmpty == true
                                  ? '${_inspectedProfile!.nickname} (@${_inspectedAccount!.accountId})'
                                  : '@${_inspectedAccount!.accountId}',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (_inspectedProfile != null)
                              Text(
                                '${_inspectedProfile!.fullName} • Student ID: ${_inspectedProfile!.studentId}',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Balance Badges Row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: AppColors.cspGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CSP (Layer 1)',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_inspectedAccount!.balances.csp.toStringAsFixed(2)} CSP',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: AppColors.bdpGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BDP (Layer 2)',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_inspectedAccount!.balances.bdp.toStringAsFixed(2)} BDP',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nonce: ${_inspectedAccount!.nonce} • Public Key: ${_inspectedAccount!.publicKey?.substring(0, 16) ?? "N/A"}...',
                    style: GoogleFonts.robotoMono(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, required this.onTap, required this.onCopy});
  final Block block;
  final VoidCallback onTap;
  final void Function(String, String) onCopy;

  @override
  Widget build(BuildContext context) {
    final timeStr = block.timestamp > 0
        ? DateFormat('HH:mm:ss').format(
            DateTime.fromMillisecondsSinceEpoch((block.timestamp * 1000).toInt()))
        : 'Genesis';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Block #${block.index}',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${block.transactions.length} txs',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    timeStr,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hash: ${block.hash.isNotEmpty ? "${block.hash.substring(0, 20)}..." : "N/A"}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textMuted),
                    onPressed: () => onCopy(block.hash, 'Block hash'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Validator: ',
                    style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                  ),
                  Expanded(
                    child: Text(
                      block.validator.isNotEmpty ? block.validator : 'Genesis / System',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

class _BlockDetailSheet extends StatelessWidget {
  const _BlockDetailSheet({required this.block});
  final Block block;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.paddingOf(context).bottom +
              20,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
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
                  'Block #${block.index} Review',
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
            const SizedBox(height: 14),
            _DetailRow(label: 'Block Hash', value: block.hash),
            _DetailRow(label: 'Prev Hash', value: block.prevHash),
            _DetailRow(label: 'Validator', value: block.validator),
            _DetailRow(label: 'State Hash', value: block.stateHash),
            _DetailRow(label: 'Confirmed', value: '${block.transactions.length} transactions'),
            const SizedBox(height: 16),
            Text(
              'Transactions in Block (${block.transactions.length})',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (block.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No transactions in this block.',
                    style: GoogleFonts.outfit(color: AppColors.textMuted)),
              )
            else
              ...block.transactions.map((tx) {
                final action = (tx['action'] ?? 'TX').toString();
                final sender = (tx['sender'] ?? 'SYSTEM').toString();
                final payload = tx['payload'] as Map<String, dynamic>? ?? {};

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassStroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            action,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandTeal,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'from @$sender',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        payload.isNotEmpty ? payload.toString() : tx.toString(),
                        style: GoogleFonts.robotoMono(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isNotEmpty ? value : 'N/A',
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
