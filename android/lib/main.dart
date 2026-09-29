import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/platform_bridge.dart';
import 'theme/corda_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CordaApp());
}

class CordaApp extends StatelessWidget {
  const CordaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Corda',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: CordaTheme.lightTheme(),
      darkTheme: CordaTheme.darkTheme(),
      home: const CordaAppBootstrap(),
    );
  }
}

class CordaAppBootstrap extends StatefulWidget {
  const CordaAppBootstrap({super.key});

  @override
  State<CordaAppBootstrap> createState() => _CordaAppBootstrapState();
}

class _CordaAppBootstrapState extends State<CordaAppBootstrap> {
  bool _isLoading = true;
  bool _hasPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final status = await PlatformBridge.instance.checkPermissions();
    if (mounted) {
      setState(() {
        _hasPermissions = status.accessibility;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: CordaTheme.aquaGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Corda',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'The invisible cord between your Mac and Android',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: CordaTheme.aquaPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasPermissions) {
      return const DashboardScreen();
    } else {
      return const OnboardingScreen();
    }
  }
}
