import 'package:flutter/material.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';
import 'main_navigation_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  PermissionStatusModel _status = const PermissionStatusModel(
    accessibility: false,
    batteryIgnored: false,
    notification: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  Future<void> _refreshPermissions() async {
    final status = await PlatformBridge.instance.checkPermissions();
    if (mounted) {
      setState(() {
        _status = status;
      });
      // If user enabled accessibility and is on step 2, move to next step
      if (status.accessibility && _currentPage == 1) {
        _pageController.animateToPage(
          2,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _navigateToDashboard() {
    PlatformBridge.instance.startForegroundService();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigationShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Header with Corda Branding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/logo_corda.png',
                      width: 38,
                      height: 38,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: CordaTheme.aquaGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.link_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Corda',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'The invisible cord between your Mac and Android',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Stepper Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final isActive = index == _currentPage;
                final isDone = (index == 0 && _status.notification) ||
                    (index == 1 && _status.accessibility) ||
                    (index == 2 && _status.batteryIgnored);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isDone
                        ? CordaTheme.mintGreen
                        : isActive
                            ? CordaTheme.aquaPrimary
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Step Content Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildStepNotification(context),
                  _buildStepAccessibility(context),
                  _buildStepBattery(context),
                ],
              ),
            ),

            // Bottom Navigation Actions
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    OutlinedButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Text('Back'),
                    )
                  else
                    TextButton(
                      onPressed: _navigateToDashboard,
                      child: Text(
                        'Skip Setup',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const Spacer(),
                  if (_currentPage < 2)
                    ElevatedButton(
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Row(
                        children: [
                          Text('Next'),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CordaTheme.aquaPrimary,
                      ),
                      onPressed: _navigateToDashboard,
                      child: const Row(
                        children: [
                          Text('Get Started with Corda'),
                          SizedBox(width: 8),
                          Icon(Icons.check_circle_rounded, size: 18),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepNotification(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CordaTheme.aquaPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              size: 56,
              color: CordaTheme.aquaPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Silent Background Service',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Corda runs a silent, low-priority background service to maintain a seamless local connection with your Mac without intrusive notifications.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  _status.notification ? Icons.check_circle_rounded : Icons.info_outline,
                  color: _status.notification ? CordaTheme.mintGreen : CordaTheme.amberWarning,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status.notification
                        ? 'Notification Permission Active'
                        : 'Silent notification required for background sync',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepAccessibility(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CordaTheme.aquaCyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.accessibility_new_rounded,
              size: 56,
              color: CordaTheme.aquaPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Instant Clipboard Sync',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Allows Corda to detect when you copy text or links across your apps, syncing them instantly to your Mac in the background.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, size: 18, color: CordaTheme.aquaPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'End-to-End Encrypted: Copied text is securely transferred directly to your Mac.',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _status.accessibility
                  ? CordaTheme.mintGreen
                  : CordaTheme.aquaPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              PlatformBridge.instance.openAccessibilitySettings();
            },
            icon: Icon(
              _status.accessibility
                  ? Icons.check_circle_rounded
                  : Icons.open_in_new_rounded,
            ),
            label: Text(
              _status.accessibility
                  ? 'Clipboard Sync Active ✓'
                  : 'Enable in Accessibility Settings',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBattery(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CordaTheme.mintGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.battery_charging_full_rounded,
              size: 56,
              color: CordaTheme.mintGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Background Activity',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Exempt Corda from battery restrictions so Android does not pause sync while your screen is off. Corda uses negligible battery (<1.5% daily).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _status.batteryIgnored
                  ? CordaTheme.mintGreen
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: _status.batteryIgnored
                  ? Colors.white
                  : colorScheme.onSurface,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              PlatformBridge.instance.openBatterySettings();
            },
            icon: Icon(
              _status.batteryIgnored
                  ? Icons.check_circle_rounded
                  : Icons.bolt_rounded,
              color: _status.batteryIgnored ? Colors.white : CordaTheme.amberWarning,
            ),
            label: Text(
              _status.batteryIgnored
                  ? 'Background Activity Allowed ✓'
                  : 'Allow Background Activity',
            ),
          ),
        ],
      ),
    );
  }
}
