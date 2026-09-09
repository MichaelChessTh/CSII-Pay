import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/domain/crypto_utils.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.startWithScanner = false, this.prefill});

  final bool startWithScanner;
  final QrPayload? prefill;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedToken = 'CSP';
  String? _selectedTeam; // null = Personal, non-null = team name
  bool _showScanner = false;
  bool _isSending = false;
  String? _error;
  MobileScannerController? _scannerCtrl;

  Timer? _debounce;
  String? _recipientNickname;
  Map<String, dynamic>? _recipientTeamInfo;
  bool _isResolvingNickname = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletViewModel>().loadMyGroups();
    });
    if (widget.prefill != null) {
      _recipientCtrl.text = widget.prefill!.accountId;
      if (widget.prefill!.amount != null) {
        _amountCtrl.text = widget.prefill!.amount.toString();
      }
      if (widget.prefill!.token != null) {
        _selectedToken = widget.prefill!.token!;
      }
      _resolveRecipientNickname(widget.prefill!.accountId);
    }
    if (widget.startWithScanner) {
      _showScanner = true;
      _initScanner();
    }
  }

  void _initScanner() {
    _scannerCtrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _scannerCtrl?.dispose();
    super.dispose();
  }

  void _onRecipientChanged(String val) {
    _debounce?.cancel();
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _recipientNickname = null;
        _recipientTeamInfo = null;
        _isResolvingNickname = false;
      });
      return;
    }
    setState(() => _isResolvingNickname = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      await _lookupRecipient(trimmed);
    });
  }

  Future<void> _lookupRecipient(String trimmed) async {
    final vm = context.read<WalletViewModel>();

    // 1. Check if recipient is a verified team account on blockchain
    final teamRes = await vm.api.getGroupInfo(trimmed);
    if (teamRes.success && teamRes.data != null) {
      if (mounted) {
        setState(() {
          _recipientTeamInfo = teamRes.data;
          _recipientNickname = null;
          _isResolvingNickname = false;
          _selectedToken = 'CSP'; // Teams only accept CSP
        });
      }
      return;
    }

    // 2. Otherwise check personal account nickname in database
    final nick = await vm.getNickname(trimmed);
    if (mounted) {
      setState(() {
        _recipientNickname = nick;
        _recipientTeamInfo = null;
        _isResolvingNickname = false;
      });
    }
  }

  void _resolveRecipientNickname(String accountId) {
    final trimmed = accountId.trim();
    if (trimmed.isEmpty) return;
    setState(() => _isResolvingNickname = true);
    _lookupRecipient(trimmed);
  }

  void _handleQrResult(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    // Check if team join QR was scanned
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['type'] == 'GROUP_JOIN') {
        final gname = data['group_name'] as String?;
        if (gname != null && gname.isNotEmpty) {
          setState(() {
            _showScanner = false;
            _recipientCtrl.text = gname;
            _selectedToken = 'CSP';
          });
          _resolveRecipientNickname(gname);
          _scannerCtrl?.dispose();
          _scannerCtrl = null;
          return;
        }
      }
    } catch (_) {}

    final payload = QrPayload.tryParse(raw);
    if (payload != null) {
      setState(() {
        _showScanner = false;
        _recipientCtrl.text = payload.accountId;
        if (payload.amount != null) _amountCtrl.text = payload.amount.toString();
        if (payload.token != null) _selectedToken = payload.token!;
      });
      _resolveRecipientNickname(payload.accountId);
      _scannerCtrl?.dispose();
      _scannerCtrl = null;
    }
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0.0;
  double get _fee => calculateFee(_selectedToken, _amount);
  double get _total => _amount + _fee;

  Future<void> _send() async {
    final vm = context.read<WalletViewModel>();
    if (_recipientCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Recipient is required');
      return;
    }
    if (_amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    final err = await vm.transfer(
      recipient: _recipientCtrl.text.trim(),
      token: _selectedToken,
      amount: _amount,
      fromTeam: _selectedTeam,
    );

    if (!mounted) return;
    if (err == null) {
      // Success
      _showSuccessSheet();
    } else {
      setState(() {
        _error = err;
        _isSending = false;
      });
    }
  }

  void _showSuccessSheet() {
    setState(() => _isSending = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isDismissible: false,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'Transaction Submitted!',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ${_amount.toStringAsFixed(4)} $_selectedToken transfer to ${_recipientCtrl.text.trim()} has been submitted to the mempool.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GradientButton(
              label: 'Done',
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showScanner) {
      return _ScannerView(
        controller: _scannerCtrl!,
        onDetect: _handleQrResult,
        onClose: () {
          setState(() => _showScanner = false);
          _scannerCtrl?.dispose();
          _scannerCtrl = null;
        },
        onManualInput: (raw) {
          final payload = QrPayload.tryParse(raw);
          if (payload != null) {
            setState(() {
              _showScanner = false;
              _recipientCtrl.text = payload.accountId;
              if (payload.amount != null) _amountCtrl.text = payload.amount.toString();
              if (payload.token != null) _selectedToken = payload.token!;
            });
          }
          _scannerCtrl?.dispose();
          _scannerCtrl = null;
        },
      );
    }

    final vm = context.watch<WalletViewModel>();
    final myGroups = vm.myGroups;
    final isTeam = _selectedTeam != null;
    final selectedTeamData = isTeam
        ? myGroups.firstWhere(
            (g) => g['name'] == _selectedTeam,
            orElse: () => <String, dynamic>{},
          )
        : null;

    final currentBalance = isTeam
        ? ((selectedTeamData?['balance'] as num?)?.toDouble() ?? 0.0)
        : (_selectedToken == 'CSP'
            ? (vm.account?.balances.csp ?? 0.0)
            : (vm.account?.balances.bdp ?? 0.0));

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Send Tokens'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () {
              _initScanner();
              setState(() => _showScanner = true);
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pay From Wallet Selector
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pay From Wallet',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (isTeam)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Team Account',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.brandCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            avatar: const Icon(Icons.person, size: 16),
                            label: Text('Personal (${(vm.account?.balances.csp ?? 0.0).toStringAsFixed(1)} CSP)'),
                            selected: _selectedTeam == null,
                            selectedColor: AppColors.brandCyan.withValues(alpha: 0.3),
                            backgroundColor: AppColors.bgCard,
                            labelStyle: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _selectedTeam == null ? Colors.white : AppColors.textSecondary,
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _selectedTeam = null);
                            },
                          ),
                          ...myGroups.map((g) {
                            final gname = g['name']?.toString() ?? '';
                            final gbal = (g['balance'] as num?)?.toDouble() ?? 0.0;
                            final selected = _selectedTeam == gname;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                avatar: const Icon(Icons.groups_rounded, size: 16),
                                label: Text('$gname (${gbal.toStringAsFixed(1)} CSP)'),
                                selected: selected,
                                selectedColor: AppColors.brandGold.withValues(alpha: 0.35),
                                backgroundColor: AppColors.bgCard,
                                labelStyle: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.textSecondary,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedTeam = gname;
                                      _selectedToken = 'CSP';
                                    });
                                  }
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Token selector with current balance
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Token',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (_selectedToken == 'CSP'
                                    ? AppColors.cspColor
                                    : AppColors.bdpColor)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_selectedToken == 'CSP'
                                      ? AppColors.cspColor
                                      : AppColors.bdpColor)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 12,
                                color: _selectedToken == 'CSP'
                                    ? AppColors.cspColor
                                    : AppColors.bdpColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Balance: ${currentBalance.toStringAsFixed(2)} $_selectedToken',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedToken == 'CSP'
                                      ? AppColors.cspColor
                                      : AppColors.bdpColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _TokenSelector(
                          token: 'CSP',
                          selected: _selectedToken == 'CSP',
                          gradient: AppColors.cspGradient,
                          onTap: () => setState(() => _selectedToken = 'CSP'),
                        ),
                        if (!isTeam && _recipientTeamInfo == null) ...[
                          const SizedBox(width: 12),
                          _TokenSelector(
                            token: 'BDP',
                            selected: _selectedToken == 'BDP',
                            gradient: AppColors.bdpGradient,
                            onTap: () => setState(() => _selectedToken = 'BDP'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Recipient with dynamic Nickname resolution
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recipient',
                        style: GoogleFonts.outfit(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _recipientCtrl,
                      onChanged: _onRecipientChanged,
                      style: GoogleFonts.outfit(
                          color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Account ID or Username',
                        prefixIcon: const Icon(Icons.person_outline_rounded,
                            color: AppColors.brandTeal, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded,
                              color: AppColors.brandTeal, size: 20),
                          onPressed: () {
                            _initScanner();
                            setState(() => _showScanner = true);
                          },
                        ),
                      ),
                    ),
                    if (_isResolvingNickname) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.brandTeal),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Checking recipient nickname in database...',
                            style: GoogleFonts.outfit(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ] else if (_recipientTeamInfo != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_rounded,
                                          color: Color(0xFF10B981), size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'VERIFIED TEAM',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF10B981),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => _showTeamDetailsSheet(_recipientTeamInfo!),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'View Details',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF10B981),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: const Color(0xFF10B981),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.arrow_forward_ios_rounded,
                                          color: Color(0xFF10B981), size: 10),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.groups_rounded,
                                    color: Color(0xFF10B981), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _recipientTeamInfo!['name']?.toString() ?? _recipientCtrl.text.trim(),
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if ((_recipientTeamInfo!['description']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _recipientTeamInfo!['description'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _showTeamDetailsSheet(_recipientTeamInfo!),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        color: Color(0xFF10B981), size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'View Team Description & Members',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_recipientNickname != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.brandTeal.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_rounded,
                                color: AppColors.brandTeal, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Recipient: $_recipientNickname',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '@${_recipientCtrl.text.trim()} (Database Verified)',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.brandTeal,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_recipientCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Recipient: @${_recipientCtrl.text.trim()} (No nickname registered)',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Amount with balance display and MAX button
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount',
                            style: GoogleFonts.outfit(
                                fontSize: 13, color: AppColors.textSecondary)),
                        GestureDetector(
                          onTap: () {
                            if (currentBalance > 0) {
                              final maxVal = _selectedToken == 'BDP'
                                  ? (currentBalance / 1.01)
                                  : (currentBalance > 500
                                      ? currentBalance / 1.02
                                      : (currentBalance > 150
                                          ? currentBalance / 1.01
                                          : currentBalance));
                              _amountCtrl.text = maxVal.toStringAsFixed(2);
                              setState(() {});
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'USE MAX',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandTeal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.outfit(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: GoogleFonts.outfit(
                            color: AppColors.textMuted,
                            fontSize: 24,
                            fontWeight: FontWeight.w700),
                        suffixText: _selectedToken,
                        suffixStyle: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 16),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_amount > 0) ...[
                      const SizedBox(height: 12),
                      const Divider(color: AppColors.glassStroke),
                      const SizedBox(height: 8),
                      _FeeRow(
                          label: 'Network Fee',
                          value:
                              '${_fee.toStringAsFixed(4)} $_selectedToken (${feeLabel(_selectedToken, _amount)})'),
                      const SizedBox(height: 4),
                      _FeeRow(
                          label: 'Total Deducted',
                          value: '${_total.toStringAsFixed(4)} $_selectedToken',
                          highlight: true),
                    ],
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: GoogleFonts.outfit(
                          color: AppColors.error, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 24),
              GradientButton(
                label: 'Review & Send',
                icon: Icons.send_rounded,
                onPressed: _amount <= 0 || _recipientCtrl.text.trim().isEmpty
                    ? null
                    : () => _reviewAndSend(currentBalance),
                isLoading: _isSending || _isResolvingNickname,
                width: double.infinity,
                height: 56,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reviewAndSend(double currentBalance) async {
    final recipient = _recipientCtrl.text.trim();
    if (recipient.isEmpty || _amount <= 0) return;

    if (_recipientNickname == null && _recipientTeamInfo == null) {
      setState(() => _isResolvingNickname = true);
      await _lookupRecipient(recipient);
      if (mounted) {
        setState(() => _isResolvingNickname = false);
      }
    }
    if (!mounted) return;
    _showConfirmSheet(currentBalance);
  }

  void _showTeamDetailsSheet(Map<String, dynamic> team) {
    final vm = context.read<WalletViewModel>();
    final teamName = team['name']?.toString() ?? 'Team';
    final desc = (team['description']?.toString() ?? '').trim();
    final creator = team['creator']?.toString() ?? '';
    final balance = (team['balance'] as num?)?.toDouble() ?? 0.0;

    final rawMembers = team['members'];
    final List<String> memberIds = [];
    if (rawMembers is Map) {
      memberIds.addAll(rawMembers.keys.map((k) => k.toString()));
    } else if (rawMembers is List) {
      memberIds.addAll(rawMembers.map((e) => e.toString()));
    }

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.groups_rounded,
                            color: Color(0xFF10B981), size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  teamName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'VERIFIED',
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFF10B981),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Shared Team Treasury: ${balance.toStringAsFixed(2)} CSP',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Project / Team Description',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgDeep,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassStroke),
                  ),
                  child: Text(
                    desc.isNotEmpty ? desc : 'No description provided for this team.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Team Members (${memberIds.length})',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (creator.isNotEmpty)
                      Text(
                        'Lead: @$creator',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: memberIds.isEmpty
                      ? Center(
                          child: Text(
                            'No members found in team.',
                            style: GoogleFonts.outfit(
                                color: AppColors.textMuted, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: memberIds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final mid = memberIds[idx];
                            final isLead = mid == creator;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.bgDeep,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassStroke),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF10B981)
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      mid.isNotEmpty ? mid[0].toUpperCase() : '?',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF10B981),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FutureBuilder<String?>(
                                      future: vm.getNickname(mid),
                                      builder: (context, snapshot) {
                                        final nick = snapshot.data;
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    nick != null && nick.isNotEmpty
                                                        ? nick
                                                        : '@$mid',
                                                    style: GoogleFonts.outfit(
                                                      color: AppColors.textPrimary,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isLead) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.brandTeal
                                                          .withValues(alpha: 0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'LEAD',
                                                      style: GoogleFonts.outfit(
                                                        color: AppColors.brandTeal,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (nick != null && nick.isNotEmpty)
                                              Text(
                                                '@$mid',
                                                style: GoogleFonts.outfit(
                                                  color: AppColors.textMuted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Close',
                  onPressed: () => Navigator.pop(ctx),
                  width: double.infinity,
                  height: 48,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showConfirmSheet(double currentBalance) {
    final isRecipientTeam = _recipientTeamInfo != null;
    final teamName = _recipientTeamInfo?['name']?.toString() ?? _recipientCtrl.text.trim();

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
                  'Confirm Transaction',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                // Prominent Recipient & Nickname / Team Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (isRecipientTeam
                            ? const Color(0xFF10B981)
                            : AppColors.brandTeal)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (isRecipientTeam
                              ? const Color(0xFF10B981)
                              : AppColors.brandTeal)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRecipientTeam
                              ? const Color(0xFF10B981).withValues(alpha: 0.25)
                              : null,
                          gradient: isRecipientTeam ? null : AppColors.brandGradient,
                        ),
                        child: Center(
                          child: isRecipientTeam
                              ? const Icon(Icons.groups_rounded,
                                  color: Color(0xFF10B981), size: 24)
                              : Text(
                                  (_recipientNickname != null &&
                                          _recipientNickname!.isNotEmpty)
                                      ? _recipientNickname![0].toUpperCase()
                                      : (_recipientCtrl.text.trim().isNotEmpty
                                          ? _recipientCtrl.text.trim()[0].toUpperCase()
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
                              isRecipientTeam
                                  ? 'Sending to Team Account:'
                                  : 'Sending to Recipient:',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              isRecipientTeam
                                  ? teamName
                                  : (_recipientNickname != null &&
                                          _recipientNickname!.isNotEmpty
                                      ? _recipientNickname!
                                      : '@${_recipientCtrl.text.trim()}'),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              isRecipientTeam
                                  ? 'Verified Team Account (CSP Only)'
                                  : '@${_recipientCtrl.text.trim()} (Database Verified)',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: isRecipientTeam
                                    ? const Color(0xFF10B981)
                                    : AppColors.brandTeal,
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
                _ConfirmRow(
                  label: 'Paying With',
                  value: '$_selectedToken (Bal: ${currentBalance.toStringAsFixed(2)})',
                ),
                if (isRecipientTeam) ...[
                  _ConfirmRow(
                    label: 'Team Name',
                    value: teamName,
                    highlight: true,
                  ),
                  const _ConfirmRow(
                    label: 'Account Status',
                    value: 'Verified Team',
                    highlight: true,
                  ),
                  if ((_recipientTeamInfo?['description']?.toString() ?? '').isNotEmpty)
                    _ConfirmRow(
                      label: 'Description',
                      value: _recipientTeamInfo!['description'].toString(),
                    ),
                ] else ...[
                  _ConfirmRow(
                    label: 'Recipient Nickname',
                    value: _recipientNickname ?? 'Not registered',
                    highlight: _recipientNickname != null,
                  ),
                  _ConfirmRow(
                    label: 'Recipient Username',
                    value: '@${_recipientCtrl.text.trim()}',
                  ),
                ],
                _ConfirmRow(
                    label: 'Amount',
                    value: '${_amount.toStringAsFixed(4)} $_selectedToken'),
                _ConfirmRow(
                    label: 'Network Fee',
                    value: '${_fee.toStringAsFixed(4)} $_selectedToken'),
                _ConfirmRow(
                    label: 'Total Deducted',
                    value: '${_total.toStringAsFixed(4)} $_selectedToken',
                    highlight: true),
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Confirm & Send',
                  icon: Icons.check_rounded,
                  isLoading: _isSending,
                  onPressed: _isSending
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _send();
                        },
                  width: double.infinity,
                  height: 52,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenSelector extends StatelessWidget {
  const _TokenSelector({
    required this.token,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String token;
  final bool selected;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: selected ? gradient : null,
            color: selected ? null : AppColors.bgDeep,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.glassStroke,
              width: 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: gradient.colors.first.withValues(alpha: 0.3), blurRadius: 12)]
                : null,
          ),
          child: Center(
            child: Text(
              token,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
            color: highlight ? AppColors.brandTeal : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary)),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight ? AppColors.brandTeal : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerView extends StatefulWidget {
  const _ScannerView({
    required this.controller,
    required this.onDetect,
    required this.onClose,
    required this.onManualInput,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onClose;
  final void Function(String) onManualInput;

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  final _manualCtrl = TextEditingController();

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Scanner
            MobileScanner(
              controller: widget.controller,
              onDetect: widget.onDetect,
            ),
            // Overlay
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.brandPurple.withValues(alpha: 0.4), width: 80),
              ),
            ),
            // Scan frame
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.brandTeal, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    // Corner highlights
                    ...['topLeft', 'topRight', 'bottomLeft', 'bottomRight']
                        .map((pos) => _Corner(position: pos)),
                  ],
                ),
              ),
            ),
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: widget.onClose,
                    ),
                    Expanded(
                      child: Text(
                        'Scan CSII-Pay QR Code',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            // Bottom manual input
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Or enter account ID manually:',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCtrl,
                            style: GoogleFonts.outfit(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Paste account ID or QR data',
                              hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
                              fillColor: AppColors.bgCard,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            if (_manualCtrl.text.trim().isNotEmpty) {
                              widget.onManualInput(_manualCtrl.text.trim());
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.position});
  final String position;

  @override
  Widget build(BuildContext context) {
    final isTop = position.startsWith('top');
    final isLeft = position.endsWith('Left');
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: AppColors.brandTeal, width: 3) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: AppColors.brandTeal, width: 3) : BorderSide.none,
            left: isLeft ? const BorderSide(color: AppColors.brandTeal, width: 3) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: AppColors.brandTeal, width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
