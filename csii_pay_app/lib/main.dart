import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:csii_pay_app/firebase_options.dart';
import 'package:csii_pay_app/data/services/node_api_service.dart';
import 'package:csii_pay_app/data/repositories/wallet_repository.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';
import 'package:csii_pay_app/ui/features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Load saved node URL if any, default to localhost:8000
  final savedUrl = await WalletRepository.getSavedNodeUrl() ?? 'http://127.0.0.1:8000';
  final api = NodeApiService(savedUrl);
  final repo = WalletRepository(api);

  runApp(CsiiPayApp(repository: repo));
}

class CsiiPayApp extends StatelessWidget {
  const CsiiPayApp({super.key, required this.repository});

  final WalletRepository repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WalletViewModel>(
      create: (_) => WalletViewModel(repository),
      child: MaterialApp(
        title: 'CSII-Pay — Web3 Bank',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const AuthGate(),
      ),
    );
  }
}
