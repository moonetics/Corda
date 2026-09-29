import 'package:flutter/material.dart';
import 'screens/main_navigation_shell.dart';
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
      themeMode: ThemeMode.dark, // Enforce macOS Sonoma Obsidian Glass Dark Theme
      theme: CordaTheme.darkTheme(),
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
        backgroundColor: CordaTheme.canvasBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo_corda.png',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              const Text(
                'Corda',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mac & Android Continuity Bridge',
                style: TextStyle(
                  fontSize: 13,
                  color: CordaTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: CordaTheme.accentBlue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasPermissions) {
      return const MainNavigationShell();
    } else {
      return const OnboardingScreen();
    }
  }
}
