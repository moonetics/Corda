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
        backgroundColor: CordaTheme.obsidianBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CordaTheme.obsidianGlass,
                  border: Border.all(color: CordaTheme.obsidianGlassBorder),
                  boxShadow: [
                    BoxShadow(
                      color: CordaTheme.aquaPrimary.withValues(alpha: 0.35),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/corda_logo_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              ShaderMask(
                shaderCallback: (bounds) => CordaTheme.aquaGradient.createShader(bounds),
                child: const Text(
                  'CORDA',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Continuity Bridge for macOS & Android',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: CordaTheme.aquaCyan,
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
