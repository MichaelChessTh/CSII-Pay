import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/domain/crypto_utils.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, this.accountId});

  final String? accountId;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedToken = 'CSP';
  bool _customAmount = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double? get _parsedAmount {
    final text = _amountCtrl.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String _buildQrData(String accountId) {
    final payload = QrPayload(
      accountId: accountId,
      amount: _parsedAmount,
      token: _parsedAmount != null ? _selectedToken : null,
      note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
    );
    return payload.toJsonString();
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Text(
              message,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: AppColors.bgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final accountId = widget.accountId ?? vm.account?.accountId ?? 'Unknown';
    final qrData = _buildQrData(accountId);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: Text(
          'Receive / My QR',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy Account ID',
            onPressed: () => _copyToClipboard(accountId, 'Account ID copied to clipboard'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // PromptPay Style Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.brandPurple.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_2_rounded, color: AppColors.brandTeal, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'CSII PromptPay Standard QR',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.brandTeal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // QR Box Card
              Center(
                child: GlassCard(
                  blur: 16,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // QR Code Container with White Glow
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPurple.withValues(alpha: 0.3),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF080B1A),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF080B1A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Account ID Display
                      Text(
                        'Account ID',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            accountId,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _copyToClipboard(accountId, 'Account ID copied!'),
                            child: const Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: AppColors.brandTeal,
                            ),
                          ),
                        ],
                      ),

                      if (_parsedAmount != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: _selectedToken == 'CSP'
                                ? AppColors.cspGradient
                                : AppColors.bdpGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Requesting: ${_parsedAmount!.toStringAsFixed(2)} $_selectedToken',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Request Specific Amount Toggle & Form
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded, color: AppColors.brandTeal, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Specify Amount & Note',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _customAmount,
                          activeThumbColor: AppColors.brandTeal, activeTrackColor: AppColors.brandTeal.withValues(alpha: 0.3),
                          onChanged: (val) {
                            setState(() {
                              _customAmount = val;
                              if (!val) {
                                _amountCtrl.clear();
                                _noteCtrl.clear();
                              }
                            });
                          },
                        ),
                      ],
                    ),

                    if (_customAmount) ...[
                      const SizedBox(height: 16),
                      // Token Toggle
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedToken = 'CSP'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: _selectedToken == 'CSP'
                                      ? AppColors.cspGradient
                                      : null,
                                  color: _selectedToken == 'CSP'
                                      ? null
                                      : AppColors.bgSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedToken == 'CSP'
                                        ? Colors.transparent
                                        : AppColors.glassStroke,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Base: CSP',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedToken = 'BDP'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: _selectedToken == 'BDP'
                                      ? AppColors.bdpGradient
                                      : null,
                                  color: _selectedToken == 'BDP'
                                      ? null
                                      : AppColors.bgSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedToken == 'BDP'
                                        ? const Color(0xFFD4AF37).withValues(alpha: 0.7)
                                        : AppColors.glassStroke,
                                    width: _selectedToken == 'BDP' ? 1.5 : 1.0,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Character: BDP',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    color: _selectedToken == 'BDP'
                                        ? const Color(0xFFFFDF73)
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Quick Amount Chips
                      Wrap(
                        spacing: 8,
                        children: [50, 100, 250, 500].map((amt) {
                          return ActionChip(
                            label: Text(
                              '+$amt $_selectedToken',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            backgroundColor: AppColors.bgSurface,
                            side: const BorderSide(color: AppColors.glassStroke),
                            onPressed: () {
                              setState(() {
                                _amountCtrl.text = amt.toString();
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Amount TextField
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Requested Amount',
                          hintText: '0.00',
                          suffixText: _selectedToken,
                          prefixIcon: const Icon(Icons.attach_money_rounded, color: AppColors.brandTeal),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),

                      // Note TextField
                      TextField(
                        controller: _noteCtrl,
                        style: GoogleFonts.outfit(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'e.g. Lunch, Coffee, Services',
                          prefixIcon: Icon(Icons.notes_rounded, color: AppColors.textSecondary),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.glassStroke),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.copy_all_rounded, color: AppColors.textPrimary),
                      label: Text(
                        'Copy Payload',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onPressed: () => _copyToClipboard(qrData, 'QR JSON Payload copied!'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'Share QR',
                      icon: Icons.share_rounded,
                      onPressed: () => _copyToClipboard(qrData, 'PromptPay QR data copied to share!'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
