import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/ui/features/send/send_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.groupName});
  final String groupName;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _group;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final vm = context.read<WalletViewModel>();
    final r = await vm.api.getGroupInfo(widget.groupName);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.success) {
        _group = r.data;
        _error = null;
      } else {
        _error = r.error;
      }
    });
  }

  String get _myAccountId => context.read<WalletViewModel>().accountId ?? '';

  bool get _isMember {
    final members = (_group?['members'] as Map<String, dynamic>? ?? {});
    return members.containsKey(_myAccountId);
  }

  void _showQrDialog() {
    final vm = context.read<WalletViewModel>();
    final qrData = jsonEncode({'type': 'GROUP_JOIN', 'group_name': widget.groupName, 'node_url': vm.api.nodeUrl});
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: Text('Team QR Code', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: qrData, version: QrVersions.auto, size: 200),
            ),
            const SizedBox(height: 12),
            Text(
              'Share this QR code with classmates to join team "${widget.groupName}".',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.outfit(color: AppColors.brandCyan)),
          ),
        ],
      ),
    );
  }

  void _showTopUpDialog() {
    final amountCtrl = TextEditingController();
    final vm = context.read<WalletViewModel>();
    final personalCsp = vm.cspBalance;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Top-Up Team Treasury', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer CSP from your personal wallet into "${widget.groupName}" shared treasury.',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              'Personal Balance: ${personalCsp.toStringAsFixed(2)} CSP',
              style: GoogleFonts.outfit(color: AppColors.brandCyan, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Amount (CSP)',
                hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.bgDeep,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassStroke)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandCyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim());
              if (amt == null || amt <= 0) return;
              Navigator.pop(ctx);
              final err = await vm.transfer(recipient: widget.groupName, token: 'CSP', amount: amt);
              if (!mounted) return;
              if (err == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deposited ${amt.toStringAsFixed(1)} CSP to team treasury!'), backgroundColor: Colors.green.shade700),
                );
                _load();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: Colors.red.shade800),
                );
              }
            },
            child: Text('Deposit', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showAddTeammateDialog() {
    final idCtrl = TextEditingController();
    final vm = context.read<WalletViewModel>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Add Teammate', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the classmate\'s account ID or student username to add them to "${widget.groupName}".',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: idCtrl,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. 6958082456 or student user',
                hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.bgDeep,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassStroke)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandCyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final invitee = idCtrl.text.trim();
              if (invitee.isEmpty) return;
              Navigator.pop(ctx);
              final r = await vm.api.inviteMember(
                accountId: _myAccountId,
                groupName: widget.groupName,
                invitee: invitee,
              );
              if (!mounted) return;
              if (r.success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Teammate "$invitee" added!'), backgroundColor: Colors.green.shade700),
                );
                _load();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(r.error ?? 'Failed to add member'), backgroundColor: Colors.red.shade800),
                );
              }
            },
            child: Text('Add Teammate', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Leave Team?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to leave "${widget.groupName}"? You will lose access to the team\'s treasury and applications.',
          style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Leave Team', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final vm = context.read<WalletViewModel>();
    final r = await vm.api.leaveGroup(accountId: _myAccountId, groupName: widget.groupName);
    if (!mounted) return;

    if (r.success) {
      await vm.loadMyGroups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You left "${widget.groupName}"'), backgroundColor: Colors.orange.shade800),
        );
        Navigator.pop(context);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error ?? 'Failed to leave team'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.bgDeep, body: Center(child: CircularProgressIndicator(color: AppColors.brandCyan)));
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.bgDeep,
        appBar: AppBar(backgroundColor: AppColors.bgDeep, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(child: Text(_error!, style: GoogleFonts.outfit(color: AppColors.textSecondary))),
      );
    }

    final g = _group!;
    final balance = (g['balance'] as num? ?? 0).toDouble();
    final members = (g['members'] as Map<String, dynamic>? ?? {});
    final description = (g['description'] as String? ?? '').trim();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        title: Row(
          children: [
            const Icon(Icons.groups_rounded, color: AppColors.brandCyan, size: 20),
            const SizedBox(width: 8),
            Text(widget.groupName, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_rounded, color: AppColors.brandCyan), onPressed: _showQrDialog),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.brandCyan,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Team Wallet'),
            Tab(text: 'Teammates'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── Tab 1: Team Wallet ──────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Treasury Hero
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F2B48), Color(0xFF081B2E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.brandCyan.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 6),
                          Text('Shared Team Treasury', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${balance.toStringAsFixed(2)} CSP',
                        style: GoogleFonts.outfit(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.brandCyan),
                      ),
                      const SizedBox(height: 18),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.black),
                              label: Text('Top-Up', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandCyan,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _showTopUpDialog,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                              label: Text('Send CSP', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.bgSurface,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.glassStroke)),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SendScreen()),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Description Card (Mandatory & Prominent)
                Text('Project Description', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.glassStroke),
                  ),
                  child: Text(
                    description.isNotEmpty ? description : 'No description provided.',
                    style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),

                // Team Metadata
                Row(
                  children: [
                    Expanded(
                      child: _infoCard(
                        icon: Icons.badge_outlined,
                        title: 'Team ID',
                        value: widget.groupName,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _infoCard(
                        icon: Icons.person_pin_circle_outlined,
                        title: 'Team Lead',
                        value: g['creator']?.toString() ?? 'None',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab 2: Teammates ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Teammates (${members.length})', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    if (_isMember)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.black),
                        label: Text('Add Member', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandCyan,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showAddTeammateDialog,
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                Expanded(
                  child: ListView.separated(
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final memberId = members.keys.elementAt(i);
                      final isCreator = memberId == g['creator'];
                      final isMe = memberId == _myAccountId;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isMe ? AppColors.brandCyan.withValues(alpha: 0.4) : AppColors.glassStroke),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.brandCyan.withValues(alpha: 0.2),
                              child: Text(
                                memberId.isNotEmpty ? memberId[0].toUpperCase() : '?',
                                style: GoogleFonts.outfit(color: AppColors.brandCyan, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(memberId, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: AppColors.brandCyan.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                          child: Text('You', style: GoogleFonts.outfit(color: AppColors.brandCyan, fontSize: 10, fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                      if (isCreator) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: AppColors.brandGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                          child: Text('Lead', style: GoogleFonts.outfit(color: AppColors.brandGold, fontSize: 10, fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text('Authorized signer on team treasury', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                if (_isMember) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 18),
                      label: Text('Leave Team', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _leaveTeam,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(title, style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
