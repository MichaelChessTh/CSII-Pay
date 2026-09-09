import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  final _urlCtrl = TextEditingController(text: 'http://127.0.0.1:8000');
  bool _connecting = false;
  String? _error;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final vm = context.read<WalletViewModel>();
    await vm.setNodeUrl(_urlCtrl.text.trim());
    await vm.init();
    if (vm.error != null) {
      setState(() {
        _error = vm.error;
        _connecting = false;
      });
      vm.clearError();
    }
  }

  Future<void> _connectViaGateway() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final vm = context.read<WalletViewModel>();
    final ok = await vm.connectToCloudGateway();
    if (!ok && mounted) {
      setState(() {
        _error = vm.error ?? 'Failed to connect via Cloudflare Gateway';
        _connecting = false;
      });
      vm.clearError();
    } else if (mounted) {
      setState(() {
        _urlCtrl.text = vm.nodeUrl;
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandPurple.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'CSII-Pay',
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Web3 Banking on Your Local Network',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 48),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect to Node',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Enter the IP:Port of your CSII-Pay node',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _urlCtrl,
                          style: GoogleFonts.outfit(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Node URL',
                            hintText: 'http://192.168.1.x:8000',
                            prefixIcon: Icon(Icons.wifi_rounded,
                                color: AppColors.brandTeal, size: 20),
                          ),
                          keyboardType: TextInputType.url,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s'))
                          ],
                          onSubmitted: (_) => _connect(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.error, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: GoogleFonts.outfit(
                                        color: AppColors.error, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        GradientButton(
                          label: 'Connect',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _connecting ? null : _connect,
                          isLoading: _connecting,
                          width: double.infinity,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFF38020), size: 18),
                          label: Text(
                            'Connect via Cloud Gateway (Off-Campus)',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFF38020),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 46),
                            side: BorderSide(color: const Color(0xFFF38020).withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            backgroundColor: const Color(0xFFF38020).withValues(alpha: 0.08),
                          ),
                          onPressed: _connecting ? null : _connectViaGateway,
                        ),
                        const SizedBox(height: 16),
                        // Quick connect shortcuts
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _QuickConnectChip(
                              label: 'Localhost',
                              url: 'http://127.0.0.1:8000',
                              onTap: (u) => setState(() => _urlCtrl.text = u),
                            ),
                            _QuickConnectChip(
                              label: ':8001',
                              url: 'http://127.0.0.1:8001',
                              onTap: (u) => setState(() => _urlCtrl.text = u),
                            ),
                            _QuickConnectChip(
                              label: 'Cloud Tunnel ⚡',
                              url: '',
                              onTap: (_) => _connectViaGateway(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '🔒 End-to-End Cryptographic Security\n⛓ Proof of Activity Consensus',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickConnectChip extends StatelessWidget {
  const _QuickConnectChip({
    required this.label,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String url;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
