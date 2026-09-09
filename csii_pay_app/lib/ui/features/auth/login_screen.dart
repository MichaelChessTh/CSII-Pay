import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _loginAccountCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();

  // Registration controllers
  final _regStudentIdCtrl = TextEditingController();
  final _regFullNameCtrl = TextEditingController();
  final _regNicknameCtrl = TextEditingController();
  final _regUsernameCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginAccountCtrl.dispose();
    _loginPassCtrl.dispose();
    _regStudentIdCtrl.dispose();
    _regFullNameCtrl.dispose();
    _regNicknameCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final vm = context.read<WalletViewModel>();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final ok = await vm.login(
      _loginAccountCtrl.text.trim(),
      _loginPassCtrl.text,
    );
    if (!ok && mounted) {
      setState(() {
        _error = vm.error;
        _isLoading = false;
      });
      vm.clearError();
    }
  }

  Future<void> _register() async {
    final studentId = _regStudentIdCtrl.text.trim();
    final fullName = _regFullNameCtrl.text.trim();
    final nickname = _regNicknameCtrl.text.trim();
    final username = _regUsernameCtrl.text.trim();
    final password = _regPassCtrl.text;
    final confirmPassword = _regConfirmCtrl.text;

    if (studentId.isEmpty) {
      setState(() => _error = 'Please enter your Student ID');
      return;
    }
    if (fullName.isEmpty) {
      setState(() => _error = 'Please enter your Full Name');
      return;
    }
    if (nickname.isEmpty) {
      setState(() => _error = 'Please enter your Nickname');
      return;
    }
    if (username.isEmpty) {
      setState(() => _error = 'Please choose a Username');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter a Password');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    final vm = context.read<WalletViewModel>();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final ok = await vm.registerWithProfile(
      studentId: studentId,
      fullName: fullName,
      nickname: nickname,
      username: username,
      password: password,
    );

    if (!ok && mounted) {
      setState(() {
        _error = vm.error;
        _isLoading = false;
      });
      vm.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandPurple.withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CSII-Pay',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Your Web3 Bank',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Tab bar
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TabBar(
                        controller: _tabs,
                        indicator: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.textSecondary,
                        labelStyle: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Sign In'),
                          Tab(text: 'Register'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Error banner
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.error.withValues(alpha: 0.3)),
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
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _LoginTab(
                      accountCtrl: _loginAccountCtrl,
                      passCtrl: _loginPassCtrl,
                      obscurePass: _obscurePass,
                      onToggleObscure: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      onLogin: _login,
                      isLoading: _isLoading,
                    ),
                    _RegisterTab(
                      studentIdCtrl: _regStudentIdCtrl,
                      fullNameCtrl: _regFullNameCtrl,
                      nicknameCtrl: _regNicknameCtrl,
                      usernameCtrl: _regUsernameCtrl,
                      passCtrl: _regPassCtrl,
                      confirmCtrl: _regConfirmCtrl,
                      onRegister: _register,
                      isLoading: _isLoading,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({
    required this.accountCtrl,
    required this.passCtrl,
    required this.obscurePass,
    required this.onToggleObscure,
    required this.onLogin,
    required this.isLoading,
  });

  final TextEditingController accountCtrl;
  final TextEditingController passCtrl;
  final bool obscurePass;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: accountCtrl,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Account ID / Username',
                hintText: 'Enter your username or account ID',
                prefixIcon: Icon(Icons.person_outline_rounded,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: obscurePass,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.brandTeal, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
              onSubmitted: (_) => onLogin(),
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Sign In',
              icon: Icons.login_rounded,
              onPressed: isLoading ? null : onLogin,
              isLoading: isLoading,
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterTab extends StatelessWidget {
  const _RegisterTab({
    required this.studentIdCtrl,
    required this.fullNameCtrl,
    required this.nicknameCtrl,
    required this.usernameCtrl,
    required this.passCtrl,
    required this.confirmCtrl,
    required this.onRegister,
    required this.isLoading,
  });

  final TextEditingController studentIdCtrl;
  final TextEditingController fullNameCtrl;
  final TextEditingController nicknameCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passCtrl;
  final TextEditingController confirmCtrl;
  final VoidCallback onRegister;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandTeal.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded,
                      color: AppColors.brandTeal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Welcome bonus: 100 BDP automatically credited!',
                      style: GoogleFonts.outfit(
                        color: AppColors.brandTeal,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: studentIdCtrl,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'e.g. 64010001',
                prefixIcon: Icon(Icons.badge_outlined,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fullNameCtrl,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'e.g. Somchai Prasert',
                prefixIcon: Icon(Icons.person_outline_rounded,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nicknameCtrl,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g. Chai',
                prefixIcon: Icon(Icons.sentiment_satisfied_alt_rounded,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: usernameCtrl,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Username (Unique Account ID)',
                hintText: 'e.g. chai99',
                prefixIcon: Icon(Icons.alternate_email_rounded,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: true,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded,
                    color: AppColors.brandTeal, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              style: GoogleFonts.outfit(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock_clock_outlined,
                    color: AppColors.brandTeal, size: 20),
              ),
              onSubmitted: (_) => onRegister(),
            ),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Create Account',
              icon: Icons.person_add_rounded,
              onPressed: isLoading ? null : onRegister,
              isLoading: isLoading,
            ),
          ],
        ),
      ),
    );
  }
}
