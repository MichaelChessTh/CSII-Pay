import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  String? _error;
  bool _isUnlocking = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKeyPress(String digit) {
    if (_enteredPin.length < 4 && !_isUnlocking) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin += digit;
        _error = null;
      });
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty && !_isUnlocking) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _verifyPin() async {
    setState(() => _isUnlocking = true);
    final vm = context.read<WalletViewModel>();
    final ok = await vm.unlockWithPin(_enteredPin);
    if (!ok && mounted) {
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0.0);
      setState(() {
        _isUnlocking = false;
        _enteredPin = '';
        _error = vm.pinAttemptsRemaining > 0
            ? 'Incorrect PIN. ${vm.pinAttemptsRemaining} attempt${vm.pinAttemptsRemaining == 1 ? '' : 's'} left.'
            : 'Too many attempts. Please sign in with your password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final nickname = vm.currentProfile?.nickname ?? vm.account?.accountId ?? 'User';
    final initial = nickname.isNotEmpty ? nickname[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(height: 16),
                          // Top Profile Info & Lock Prompt
                          Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppColors.brandGradient,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.brandPurple.withValues(alpha: 0.35),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: GoogleFonts.outfit(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Welcome Back',
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enter your 4-digit PIN for $nickname',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 28),
                              // 4 PIN Dots with shake animation
                              AnimatedBuilder(
                                animation: _shakeAnim,
                                builder: (context, child) => Transform.translate(
                                  offset: Offset(_shakeAnim.value, 0),
                                  child: child,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(4, (index) {
                                    final isFilled = index < _enteredPin.length;
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      margin: const EdgeInsets.symmetric(horizontal: 10),
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isFilled
                                            ? AppColors.brandCyan
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isFilled
                                              ? AppColors.brandCyan
                                              : AppColors.glassStroke,
                                          width: 2,
                                        ),
                                        boxShadow: isFilled
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.brandCyan.withValues(alpha: 0.5),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _error!,
                                  style: GoogleFonts.outfit(
                                    color: AppColors.error,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),

                          // Numeric Keypad
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _PinKey(label: '1', onTap: () => _onKeyPress('1')),
                                    _PinKey(label: '2', onTap: () => _onKeyPress('2')),
                                    _PinKey(label: '3', onTap: () => _onKeyPress('3')),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _PinKey(label: '4', onTap: () => _onKeyPress('4')),
                                    _PinKey(label: '5', onTap: () => _onKeyPress('5')),
                                    _PinKey(label: '6', onTap: () => _onKeyPress('6')),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _PinKey(label: '7', onTap: () => _onKeyPress('7')),
                                    _PinKey(label: '8', onTap: () => _onKeyPress('8')),
                                    _PinKey(label: '9', onTap: () => _onKeyPress('9')),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _PinKey(
                                      icon: Icons.clear_all_rounded,
                                      onTap: () {
                                        if (_enteredPin.isNotEmpty) {
                                          HapticFeedback.lightImpact();
                                          setState(() => _enteredPin = '');
                                        }
                                      },
                                    ),
                                    _PinKey(label: '0', onTap: () => _onKeyPress('0')),
                                    _PinKey(
                                      icon: Icons.backspace_outlined,
                                      onTap: _onBackspace,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Forgot PIN / Log In with Password fallback
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom + 12,
                            ),
                            child: TextButton(
                              onPressed: () {
                                // Logout without clearing credentials to prompt password entry
                                vm.logout(clearSaved: false);
                              },
                              child: Text(
                                'Sign In with Password Instead',
                                style: GoogleFonts.outfit(
                                  color: AppColors.brandCyan,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    this.label,
    this.icon,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurface.withValues(alpha: 0.6),
          border: Border.all(color: AppColors.glassStroke),
        ),
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                )
              : Icon(icon, color: AppColors.textSecondary, size: 22),
        ),
      ),
    );
  }
}
