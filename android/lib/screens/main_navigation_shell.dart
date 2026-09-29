import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';
import 'dashboard_screen.dart';
import 'file_transfer_screen.dart';
import 'settings_tab.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    PlatformBridge.instance.triggerHaptic();
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CordaTheme.obsidianBg,
      body: Stack(
        children: [
          // Background ambient gradient mesh
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    CordaTheme.aquaPrimary.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    CordaTheme.aquaCyan.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Pages
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            children: [
              DashboardScreen(
                onNavigateToTransfer: () => _onTabTapped(1),
              ),
              const FileTransferScreen(),
              const SettingsTab(),
            ],
          ),

          // Floating macOS Sonoma Liquid Glass Dock
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: _buildFloatingSonomaDock(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSonomaDock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xD90A1120),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: CordaTheme.aquaCyan.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDockItem(
                index: 0,
                icon: CupertinoIcons.macwindow,
                label: 'Dashboard',
              ),
              _buildDockItem(
                index: 1,
                icon: CupertinoIcons.arrow_up_arrow_down_circle_fill,
                label: 'Transfer',
              ),
              _buildDockItem(
                index: 2,
                icon: CupertinoIcons.gear_alt_fill,
                label: 'Pengaturan',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 18 : 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: isSelected ? CordaTheme.aquaGradient : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CordaTheme.aquaCyan.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.45),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
