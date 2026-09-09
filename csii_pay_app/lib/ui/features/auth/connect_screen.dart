import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late Animation<double> _glow;
  bool _showManualConfig = false;
  final _urlCtrl = TextEditingController();
  bool _manualConnecting = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutCubic),
    );

    _glow = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutCubic),
    );

    // Automatically trigger connection seamlessly in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    final vm = context.read<WalletViewModel>();
    _urlCtrl.text = vm.nodeUrl;
    await vm.init();
  }

  Future<void> _manualConnect() async {
    setState(() => _manualConnecting = true);
    final vm = context.read<WalletViewModel>();
    await vm.setNodeUrl(_urlCtrl.text.trim());
    await vm.init();
    if (mounted) setState(() => _manualConnecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final hasError = vm.error != null;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          bottom: true,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Glowing Pulsing Logo
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, child) {
                      return ScaleTransition(
                        scale: _pulse,
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandPurple
                                    .withValues(alpha: _glow.value),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                              BoxShadow(
                                color: AppColors.brandCyan
                                    .withValues(alpha: _glow.value * 0.5),
                                blurRadius: 25,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.diamond_outlined,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),

                  // Brand Title
                  Text(
                    'CSII-Pay',
                    style: GoogleFonts.outfit(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chulalongkorn Web3 Campus Economy',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 44),

                  // Dynamic Seamless Connection Status
                  if (!hasError) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.glassStroke),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.brandCyan,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Connecting to blockchain network...',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Error state with graceful retry
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded,
                                  color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Node temporarily unreachable',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.error,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Verify you are connected to the campus Wi-Fi or have internet access to reach the Cloudflare Gateway.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              'Retry Connection',
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600),
                            ),
                            onPressed: _autoConnect,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        setState(() => _showManualConfig = !_showManualConfig);
                      },
                      child: Text(
                        _showManualConfig
                            ? 'Hide Advanced Settings'
                            : 'Advanced Node Settings',
                        style: GoogleFonts.outfit(
                          color: AppColors.brandCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  // Optional manual configuration drawer if user ever needs custom IP
                  if (_showManualConfig) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.glassStroke),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _urlCtrl,
                            style: GoogleFonts.outfit(
                                color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Custom Node URL',
                              labelStyle: GoogleFonts.outfit(
                                  color: AppColors.textSecondary),
                              hintText: 'http://127.0.0.1:8000',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _manualConnecting
                                      ? null
                                      : _manualConnect,
                                  child: _manualConnecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Text('Connect to URL'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandCyan,
                                    foregroundColor: Colors.black,
                                  ),
                                  onPressed: () async {
                                    final ok = await vm.connectToCloudGateway();
                                    if (ok && mounted) {
                                      _urlCtrl.text = vm.nodeUrl;
                                    }
                                  },
                                  child: const Text('Cloud Gateway'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
