import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  double _initialDeposit = 0.0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Team name is required');
      return;
    }
    if (desc.isEmpty) {
      setState(() => _error = 'Description is required for team creation');
      return;
    }

    final vm = context.read<WalletViewModel>();
    final accountId = vm.accountId;
    if (accountId == null) {
      setState(() => _error = 'Not logged in');
      return;
    }

    if (_initialDeposit > 0 && vm.cspBalance < _initialDeposit) {
      setState(() => _error = 'Insufficient personal CSP balance for initial deposit (${_initialDeposit.toStringAsFixed(1)} CSP required)');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final r = await vm.api.createGroup(
      accountId: accountId,
      groupName: name,
      description: desc,
      initialDeposit: _initialDeposit,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (r.success) {
      await vm.loadMyGroups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Team "$name" created successfully!'),
          backgroundColor: Colors.green.shade700,
        ));
        Navigator.pop(context);
      }
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final cspBalance = vm.cspBalance;
    final maxDeposit = cspBalance.clamp(0.0, 500.0);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        title: Text('Create Team Account', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.brandCyan.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: AppColors.brandCyan, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Team accounts have a shared CSP treasury. All invited members can spend and post applications on behalf of the team.',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _label('Team Name (Unique ID) *'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: GoogleFonts.outfit(color: Colors.white),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]'))],
            decoration: _inputDeco('e.g. bascii_robotics'),
          ),
          const SizedBox(height: 4),
          Text('Letters, numbers, underscores and dashes only.',
              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          _label('Team Description * (Required)'),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            style: GoogleFonts.outfit(color: Colors.white),
            maxLines: 3,
            decoration: _inputDeco('Describe the purpose of this project team...'),
          ),
          const SizedBox(height: 24),

          _label('Seed Team Treasury (Optional): ${_initialDeposit.toStringAsFixed(0)} CSP'),
          const SizedBox(height: 4),
          if (maxDeposit > 0) ...[
            Row(children: [
              Text('0', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _initialDeposit.clamp(0.0, maxDeposit),
                  min: 0,
                  max: maxDeposit > 0 ? maxDeposit : 100,
                  divisions: maxDeposit > 0 ? maxDeposit.toInt() : 100,
                  activeColor: AppColors.brandCyan,
                  inactiveColor: AppColors.glassStroke,
                  onChanged: (v) => setState(() => _initialDeposit = v),
                ),
              ),
              Text(maxDeposit.toStringAsFixed(0), style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
            ]),
            Text('Your personal balance: ${cspBalance.toStringAsFixed(2)} CSP',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ] else ...[
            Text('Your personal CSP balance is 0. You can top up later.',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ],

          if (_error != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade900.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: GoogleFonts.outfit(color: Colors.red.shade200, fontSize: 13))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandCyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(
                      _initialDeposit > 0
                          ? 'Create Team & Seed ${_initialDeposit.toStringAsFixed(0)} CSP'
                          : 'Create Team Account',
                      style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500));

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
    filled: true,
    fillColor: AppColors.bgSurface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassStroke)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassStroke)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brandCyan)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
