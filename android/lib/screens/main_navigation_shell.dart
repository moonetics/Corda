import 'package:flutter/material.dart';
import '../theme/corda_theme.dart';
import 'dashboard_screen.dart';

class MainNavigationShell extends StatelessWidget {
  const MainNavigationShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CordaTheme.canvasBg,
      body: DashboardScreen(),
    );
  }
}
