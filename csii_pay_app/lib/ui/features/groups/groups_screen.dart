import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/ui/features/groups/group_detail_screen.dart';
import 'package:csii_pay_app/ui/features/groups/create_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final vm = context.read<WalletViewModel>();
    final accountId = vm.accountId;
    if (accountId == null) return;
    final r = await vm.api.getMyGroupsData(accountId);
    if (!mounted) return;
    if (r.success) {
      setState(() {
        _myGroups = List<Map<String, dynamic>>.from(r.data!['my_groups'] ?? []);
        _pendingInvites = List<Map<String, dynamic>>.from(r.data!['pending_invites'] ?? []);
        _loading = false;
        _error = null;
      });
    } else {
      setState(() { _loading = false; _error = r.error; });
    }
  }

  void _openGroup(Map<String, dynamic> group) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GroupDetailScreen(groupName: group['name'] as String),
    )).then((_) => _load());
  }

  void _createGroup() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const CreateGroupScreen(),
    )).then((_) => _load());
  }

  void _scanQr() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const _QrJoinScannerScreen(),
    )).then((_) => _load());
  }

  Future<void> _acceptInvite(Map<String, dynamic> invite) async {
    final vm = context.read<WalletViewModel>();
    final accountId = vm.accountId;
    if (accountId == null) return;
    final fee = (invite['entrance_fee'] as num? ?? 0).toDouble();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: Text('Join Team "${invite['name']}"', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'Invited by: ${invite['invitation_from']}${fee > 0 ? '\nEntrance fee: $fee CSP' : ''}\nYou will get access to the team\'s shared treasury.',
          style: GoogleFonts.outfit(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandCyan),
            onPressed: () => Navigator.pop(context, true),
            child: Text(fee > 0 ? 'Join ($fee CSP)' : 'Join Team',
                style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final r = await vm.api.joinGroup(accountId: accountId, groupName: invite['name'] as String);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.success ? 'Joined "${invite['name']}"!' : r.error ?? 'Failed'),
      backgroundColor: r.success ? Colors.green.shade700 : Colors.red.shade700,
    ));
    if (r.success) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text('Teams', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
                const Spacer(),
                IconButton(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.brandCyan, size: 28)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary)),
              ]),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brandCyan))
                  : _error != null
                      ? Center(child: Text(_error!, style: GoogleFonts.outfit(color: AppColors.textSecondary)))
                      : _myGroups.isEmpty && _pendingInvites.isEmpty
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.groups_outlined, color: AppColors.textSecondary, size: 64),
                              const SizedBox(height: 16),
                              Text('No teams yet', style: GoogleFonts.outfit(fontSize: 20, color: Colors.white70)),
                              const SizedBox(height: 8),
                              Text('Create a team account to collaborate and hire on marketplace.', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                            ]))
                          : RefreshIndicator(
                              onRefresh: _load, color: AppColors.brandCyan,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                                children: [
                                  if (_pendingInvites.isNotEmpty) ...[
                                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 6),
                                        child: Text('PENDING INVITATIONS', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1.2))),
                                    ..._pendingInvites.map((inv) => _InviteCard(invite: inv, onAccept: () => _acceptInvite(inv))),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_myGroups.isNotEmpty) ...[
                                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 6),
                                        child: Text('MY TEAMS', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1.2))),
                                    ..._myGroups.map((g) => _GroupCard(group: g, onTap: () => _openGroup(g))),
                                  ],
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        backgroundColor: AppColors.brandCyan,
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text('New Team', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});
  final Map<String, dynamic> group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = (group['balance'] as num? ?? 0).toDouble();
    final memberCount = group['member_count'] as int? ?? 0;
    final name = group['name'] as String;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00F5A0), Color(0xFF00D9F5)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(name.substring(0, 1).toUpperCase(),
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black))),
          ),
          const SizedBox(width: 14),
            Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.brandCyan.withValues(alpha: 0.3)),
                  ),
                  child: Text('TEAM',
                      style: GoogleFonts.outfit(fontSize: 9, color: AppColors.brandCyan, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(group['description'] as String? ?? '',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('$memberCount', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
                const Icon(Icons.account_balance_wallet_outlined, size: 14, color: AppColors.brandCyan),
                const SizedBox(width: 4),
                Text('${balance.toStringAsFixed(2)} CSP',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.brandCyan, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.onAccept});
  final Map<String, dynamic> invite;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.groups_rounded, color: AppColors.brandCyan),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Team: ${invite['name']}',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          Text(
            'Invited by: ${invite['invitation_from']}${((invite['entrance_fee'] as num? ?? 0) > 0) ? ' · Fee: ${invite['entrance_fee']} CSP' : ' · Free to join'}',
            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
          ),
        ])),
        ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandCyan,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          child: Text('Join Team', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _QrJoinScannerScreen extends StatefulWidget {
  const _QrJoinScannerScreen();
  @override
  State<_QrJoinScannerScreen> createState() => _QrJoinScannerScreenState();
}

class _QrJoinScannerScreenState extends State<_QrJoinScannerScreen> {
  bool _scanned = false;
  Map<String, dynamic>? _groupInfo;
  bool _loading = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] != 'GROUP_JOIN') return;
      final groupName = data['group_name'] as String?;
      if (groupName == null) return;
      _scanned = true;
      setState(() => _loading = true);
      final vm = context.read<WalletViewModel>();
      final r = await vm.api.getGroupInfo(groupName);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.success) { _groupInfo = r.data; }
        else { _error = r.error; _scanned = false; }
      });
    } catch (_) {}
  }

  Future<void> _joinGroup() async {
    final vm = context.read<WalletViewModel>();
    final accountId = vm.accountId;
    if (accountId == null || _groupInfo == null) return;
    final r = await vm.api.joinGroup(
        accountId: accountId, groupName: _groupInfo!['name'] as String);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.success ? 'Successfully joined!' : r.error ?? 'Failed'),
      backgroundColor: r.success ? Colors.green.shade700 : Colors.red.shade700,
    ));
    if (r.success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        title: Text('Scan Group QR', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandCyan))
          : _groupInfo != null ? _buildPreview() : _buildScanner(),
    );
  }

  Widget _buildScanner() => Stack(children: [
    MobileScanner(onDetect: _onDetect),
    if (_error != null)
      Positioned(bottom: 40, left: 20, right: 20,
          child: Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: GoogleFonts.outfit(color: Colors.white)))),
    Positioned(top: 20, left: 0, right: 0,
        child: Center(child: Text('Scan a group QR code', style: GoogleFonts.outfit(color: Colors.white70)))),
  ]);

  Widget _buildPreview() {
    final g = _groupInfo!;
    final members = (g['member_details'] as Map<String, dynamic>? ?? {}).keys.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00F5A0), Color(0xFF00D9F5)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(child: Text((g['name'] as String).substring(0, 1).toUpperCase(),
              style: GoogleFonts.outfit(fontSize: 38, fontWeight: FontWeight.w700, color: Colors.black))),
        )),
        const SizedBox(height: 16),
        Center(child: Text(g['name'] as String,
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(height: 6),
        Center(child: Text(g['description'] as String? ?? '',
            style: GoogleFonts.outfit(color: AppColors.textSecondary), textAlign: TextAlign.center)),
        const SizedBox(height: 24),
        _row(Icons.people_outline, 'Members', '${g['member_count'] ?? members.length}'),
        if ((g['entrance_fee'] as num? ?? 0) > 0)
          _row(Icons.toll_rounded, 'Entrance Fee', '${g['entrance_fee']} CSP'),
        _row(Icons.person_outline, 'Creator', g['creator'] as String? ?? ''),
        const SizedBox(height: 16),
        Text('Members:', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        ...members.map((m) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            const Icon(Icons.person_rounded, size: 16, color: AppColors.brandCyan),
            const SizedBox(width: 8),
            Text(m, style: GoogleFonts.outfit(color: Colors.white)),
          ]),
        )),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            onPressed: _joinGroup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              ((g['entrance_fee'] as num? ?? 0) > 0)
                  ? 'Join Team (pay ${g['entrance_fee']} CSP)'
                  : 'Join Team',
              style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 10),
      Text('$label: ', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
      Text(value, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
    ]),
  );
}
