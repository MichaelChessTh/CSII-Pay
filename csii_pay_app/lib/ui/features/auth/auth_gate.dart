import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/ui/features/home/views/home_screen.dart';
import 'package:csii_pay_app/ui/features/auth/connect_screen.dart';
import 'package:csii_pay_app/ui/features/auth/login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletViewModel>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.read<WalletViewModel>(),
      builder: (context, _) {
        final vm = context.read<WalletViewModel>();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: switch (vm.appState) {
            AppState.connecting => const ConnectScreen(key: ValueKey('connect')),
            AppState.authRequired => const LoginScreen(key: ValueKey('login')),
            AppState.authenticated => const HomeScreen(key: ValueKey('home')),
          },
        );
      },
    );
  }
}
