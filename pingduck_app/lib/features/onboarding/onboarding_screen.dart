import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/pingduck_colors.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../auth/sign_in_screen.dart';
import '../settings/presentation/privacy_settings_screen.dart';

/// 3-step onboarding flow modeled after Fing's modern sequence:
/// 1. Privacy Defaults ("Your network, your rules")
/// 2. Location & Network Access ("Enable location to detect your Wi-Fi")
/// 3. Account Creation & Smart Scans ("Join PingDuck for more smart scans")
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when onboarding is completed or skipped to launch the first scan.
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _currentPage = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _handleLocationContinue() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Permission.locationWhenInUse.request();
      } catch (_) {
        // Safe fallback in test or restricted environments
      }
    }
    _goTo(3);
  }

  Future<void> _openEmailAuth() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SignInScreen(
          startWithSignUp: true,
          lead: 'Create your free account to sync networks and alerts.',
        ),
      ),
    );
    if (signedIn == true) {
      widget.onDone();
    }
  }

  Future<void> _handleGoogleSignIn() async {
    // Navigate to sign-in screen to authenticate
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SignInScreen(
          startWithSignUp: true,
          lead: 'Sign in to sync your networks and alerts.',
        ),
      ),
    );
    if (signedIn == true) {
      widget.onDone();
    }
  }

  void _openPrivacySettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacySettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appThemeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          if (_currentPage == 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 380,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        PingDuckColors.isDark
                            ? const Color(0xFF047857).withValues(alpha: 0.28)
                            : const Color(0xFF6EE7B7).withValues(alpha: 0.50),
                        theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                // Top Navigation / Progress Indicator Bar
                if (_currentPage > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          color: theme.colorScheme.onSurface,
                          tooltip: 'Back',
                          onPressed: () => _goTo(_currentPage - 1),
                        ),
                        const Spacer(),
                        // Progress Dots
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (index) {
                            final active = index == _currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active ? PingDuckColors.route : theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48, height: 48),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 24),

                // Page Content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // Step 0: Discover & Protect Wi-Fi
                      _OnboardingStepLayout(
                        illustration: const _DiscoverProtectIllustration(),
                        title: 'Discover and protect your Wi-Fi',
                        body:
                            'See every device on your network, spot intruders instantly, test your speed, and stay informed about outages.',
                        primaryButtonText: 'Get started',
                        onPrimaryPressed: () => _goTo(1),
                      ),

                      // Step 1: Privacy Defaults
                      _OnboardingStepLayout(
                        illustration: const _PrivacyLockIllustration(),
                        title: 'Your network, your rules',
                        body:
                            "We've set privacy defaults that protect you from the start. Review your preferences anytime in the App settings.",
                        primaryButtonText: 'Agree and continue',
                        onPrimaryPressed: () => _goTo(2),
                        secondaryButtonText: 'Review settings and policies',
                        onSecondaryPressed: _openPrivacySettings,
                        secondaryButtonColor: PingDuckColors.route,
                      ),

                      // Step 2: Location Access
                      _OnboardingStepLayout(
                        illustration: const _LocationWifiIllustration(),
                        title: 'Enable location to detect your Wi-Fi',
                        body:
                            'PingDuck uses location access to identify your exact network and keep your device names consistent across scans.',
                        primaryButtonText: 'Continue',
                        onPrimaryPressed: _handleLocationContinue,
                        secondaryButtonText: 'Use without Wi-Fi details',
                        onSecondaryPressed: () => _goTo(3),
                        secondaryButtonColor: PingDuckColors.route,
                      ),

                      // Step 3: Account Creation & Smart Scans
                      _AccountStepLayout(
                        onGoogleSignIn: _handleGoogleSignIn,
                        onEmailAuth: _openEmailAuth,
                        onSkip: widget.onDone,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard layout for onboarding steps 1 and 2.
class _OnboardingStepLayout extends StatelessWidget {
  const _OnboardingStepLayout({
    required this.illustration,
    required this.title,
    required this.body,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    this.secondaryButtonText,
    this.onSecondaryPressed,
    this.secondaryButtonColor,
  });

  final Widget illustration;
  final String title;
  final String body;
  final String primaryButtonText;
  final VoidCallback onPrimaryPressed;
  final String? secondaryButtonText;
  final VoidCallback? onSecondaryPressed;
  final Color? secondaryButtonColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    // Illustration
                    illustration,
                    const SizedBox(height: 40),
                    // Headline
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 27,
                        height: 34 / 27,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Body text
                    Text(
                      body,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        height: 24 / 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(flex: 3),
                    // Actions
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PingDuckColors.route,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onPrimaryPressed,
                        child: Text(
                          primaryButtonText,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (secondaryButtonText != null && onSecondaryPressed != null) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: secondaryButtonColor ?? PingDuckColors.route,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        ),
                        onPressed: onSecondaryPressed,
                        child: Text(
                          secondaryButtonText!,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: secondaryButtonColor ?? PingDuckColors.route,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Step 3 layout: Account creation with Google and Email authentication options.
class _AccountStepLayout extends StatelessWidget {
  const _AccountStepLayout({
    required this.onGoogleSignIn,
    required this.onEmailAuth,
    required this.onSkip,
  });

  final VoidCallback onGoogleSignIn;
  final VoidCallback onEmailAuth;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    const _AccountSmartScanIllustration(),
                    const SizedBox(height: 40),
                    Text(
                      'Join PingDuck for more smart scans',
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 27,
                        height: 34 / 27,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create your free account to get network alerts, extra scans today, outage updates, and priority support.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        height: 24 / 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(flex: 3),
                    // Sign in with Google Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1F1F1F),
                          elevation: 0,
                          side: BorderSide(color: theme.colorScheme.outlineVariant),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onGoogleSignIn,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: const Size(20, 20),
                              painter: const _GoogleLogoPainter(),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(
                              child: Text(
                                'Sign in with Google',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F1F1F),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Continue with email button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          side: BorderSide(color: theme.colorScheme.outline),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onEmailAuth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mail_outline, size: 20),
                            const SizedBox(width: 10),
                            const Flexible(
                              child: Text(
                                'Or continue with email',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // I'll think about it (skip to scans)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                      onPressed: onSkip,
                      child: Text(
                        "I'll think about it",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


// =============================================================================
// VECTOR ILLUSTRATIONS
// =============================================================================

/// Step 0: Wi-Fi broadcast waves inspected with a magnifying glass with scanning eye.
class _DiscoverProtectIllustration extends StatelessWidget {
  const _DiscoverProtectIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = PingDuckColors.isDark;
    return SizedBox(
      width: 160,
      height: 160,
      child: CustomPaint(
        painter: _DiscoverProtectPainter(
          strokeColor: theme.colorScheme.onSurface,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _DiscoverProtectPainter extends CustomPainter {
  const _DiscoverProtectPainter({
    required this.strokeColor,
    required this.isDark,
  });

  final Color strokeColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const techBlue = Color(0xFF0070F3);

    final linePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bluePaint = Paint()
      ..color = techBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1. Wi-Fi wave arcs radiating up-left
    final wifiOrigin = Offset(size.width * 0.46, size.height * 0.80);
    final radii = [15.0, 31.0, 47.0, 63.0];
    for (int i = 0; i < radii.length; i++) {
      final r = radii[i];
      final rect = Rect.fromCircle(center: wifiOrigin, radius: r);
      canvas.drawArc(rect, -math.pi * 0.88, math.pi * 0.50, false, linePaint);
    }
    // Dot at the base of Wi-Fi waves
    final dotPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.46, size.height * 0.80 - 2), 2.5, dotPaint);

    // 2. Magnifying glass lens
    final lensCenter = Offset(size.width * 0.57, size.height * 0.38);
    final lensRadius = size.width * 0.22;
    canvas.drawCircle(lensCenter, lensRadius, linePaint);

    // Magnifying glass handle extending down-right
    final handleAngle = math.pi * 0.26;
    final handleStart = Offset(
      lensCenter.dx + math.cos(handleAngle) * (lensRadius - 1),
      lensCenter.dy + math.sin(handleAngle) * (lensRadius - 1),
    );
    final handleEnd = Offset(
      lensCenter.dx + math.cos(handleAngle) * (lensRadius + 24),
      lensCenter.dy + math.sin(handleAngle) * (lensRadius + 24),
    );
    final handlePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(handleStart, handleEnd, handlePaint);

    // 3. Scanning Eye inside the lens
    final eyeWidth = lensRadius * 0.62;
    final eyeHeight = lensRadius * 0.36;

    final eyePath = Path();
    eyePath.moveTo(lensCenter.dx - eyeWidth, lensCenter.dy);
    eyePath.quadraticBezierTo(
      lensCenter.dx,
      lensCenter.dy - eyeHeight,
      lensCenter.dx + eyeWidth,
      lensCenter.dy,
    );
    eyePath.quadraticBezierTo(
      lensCenter.dx,
      lensCenter.dy + eyeHeight,
      lensCenter.dx - eyeWidth,
      lensCenter.dy,
    );
    canvas.drawPath(eyePath, bluePaint);

    // Eye pupil
    final pupilPaint = Paint()
      ..color = techBlue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lensCenter, 3.2, pupilPaint);

    // 4. Focus target brackets around the eye
    final bOffset = lensRadius * 0.54;
    const bLen = 6.0;
    // Top-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(lensCenter.dx - bOffset, lensCenter.dy - bOffset + bLen)
        ..lineTo(lensCenter.dx - bOffset, lensCenter.dy - bOffset)
        ..lineTo(lensCenter.dx - bOffset + bLen, lensCenter.dy - bOffset),
      bluePaint,
    );
    // Top-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(lensCenter.dx + bOffset - bLen, lensCenter.dy - bOffset)
        ..lineTo(lensCenter.dx + bOffset, lensCenter.dy - bOffset)
        ..lineTo(lensCenter.dx + bOffset, lensCenter.dy - bOffset + bLen),
      bluePaint,
    );
    // Bottom-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(lensCenter.dx - bOffset, lensCenter.dy + bOffset - bLen)
        ..lineTo(lensCenter.dx - bOffset, lensCenter.dy + bOffset)
        ..lineTo(lensCenter.dx - bOffset + bLen, lensCenter.dy + bOffset),
      bluePaint,
    );
    // Bottom-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(lensCenter.dx + bOffset - bLen, lensCenter.dy + bOffset)
        ..lineTo(lensCenter.dx + bOffset, lensCenter.dy + bOffset)
        ..lineTo(lensCenter.dx + bOffset, lensCenter.dy + bOffset - bLen),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DiscoverProtectPainter old) =>
      old.strokeColor != strokeColor || old.isDark != isDark;
}

/// Step 1: Padlock outline with key insertion and emerald sparks.
class _PrivacyLockIllustration extends StatelessWidget {
  const _PrivacyLockIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _PrivacyLockPainter(color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _PrivacyLockPainter extends CustomPainter {
  const _PrivacyLockPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final greenPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Telemetry sparks on upper-left
    canvas.drawLine(Offset(cx - 36, cy - 32), Offset(cx - 48, cy - 32), greenPaint);
    canvas.drawLine(Offset(cx - 32, cy - 42), Offset(cx - 42, cy - 54), greenPaint);
    canvas.drawLine(Offset(cx - 24, cy - 48), Offset(cx - 24, cy - 60), greenPaint);

    // 2. Padlock Shackle (top rounded loop)
    final shackleRect = RRect.fromRectAndCorners(
      Rect.fromCenter(center: Offset(cx, cy - 24), width: 44, height: 48),
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
    );
    canvas.drawRRect(shackleRect, strokePaint);

    // 3. Padlock Body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 6), width: 72, height: 56),
      const Radius.circular(12),
    );
    canvas.drawRRect(bodyRect, strokePaint);

    // 4. Emerald Keyhole
    final keyholePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final keyholePath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy + 2), radius: 5))
      ..moveTo(cx - 3.5, cy + 5)
      ..lineTo(cx - 2, cy + 13)
      ..lineTo(cx + 2, cy + 13)
      ..lineTo(cx + 3.5, cy + 5);
    canvas.drawPath(keyholePath, keyholePaint);

    // 5. Key entering the bottom-right
    final keyPath = Path()
      // Bow circle
      ..addOval(Rect.fromCircle(center: Offset(cx + 38, cy + 32), radius: 11))
      // Key shaft entering toward lock
      ..moveTo(cx + 30, cy + 24)
      ..lineTo(cx + 12, cy + 8)
      // Teeth
      ..moveTo(cx + 22, cy + 16)
      ..lineTo(cx + 25, cy + 13)
      ..moveTo(cx + 17, cy + 12)
      ..lineTo(cx + 20, cy + 9);
    canvas.drawPath(keyPath, strokePaint);

    // Hole in key bow
    canvas.drawCircle(Offset(cx + 38, cy + 32), 4, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _PrivacyLockPainter old) => old.color != color;
}

/// Step 2: Home & Office location pins with Wi-Fi radiating arches and dashed center line.
class _LocationWifiIllustration extends StatelessWidget {
  const _LocationWifiIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      height: 130,
      child: CustomPaint(
        painter: _LocationWifiPainter(color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _LocationWifiPainter extends CustomPainter {
  const _LocationWifiPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final greenPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;

    // 1. Center dashed vertical line
    const dashHeight = 7.0;
    const dashGap = 5.0;
    var currentY = 10.0;
    while (currentY < size.height - 10) {
      canvas.drawLine(
        Offset(cx, currentY),
        Offset(cx, math.min(currentY + dashHeight, size.height - 10)),
        greenPaint,
      );
      currentY += dashHeight + dashGap;
    }

    // 2. Left Pin (Home Wi-Fi)
    final leftCx = cx - 42;
    _drawPinWithWifi(canvas, Offset(leftCx, 40), greenPaint, whitePaint);

    // House outline below left pin
    final housePath = Path()
      // Roof peak
      ..moveTo(leftCx - 18, 92)
      ..lineTo(leftCx, 76)
      ..lineTo(leftCx + 18, 92)
      // Walls
      ..moveTo(leftCx - 14, 90)
      ..lineTo(leftCx - 14, 114)
      ..lineTo(leftCx + 14, 114)
      ..lineTo(leftCx + 14, 90)
      // Door
      ..moveTo(leftCx - 4, 114)
      ..lineTo(leftCx - 4, 102)
      ..lineTo(leftCx + 4, 102)
      ..lineTo(leftCx + 4, 114);
    canvas.drawPath(housePath, whitePaint);

    // 3. Right Pin (Office Wi-Fi)
    final rightCx = cx + 42;
    _drawPinWithWifi(canvas, Offset(rightCx, 40), greenPaint, whitePaint);

    // Office building outline below right pin
    final officePath = Path()
      // Building rectangle
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(rightCx, 98), width: 34, height: 34),
          const Radius.circular(4),
        ),
      );
    canvas.drawPath(officePath, whitePaint);

    // Windows grid in building
    const winW = 5.0;
    const winH = 5.0;
    canvas.drawRect(Rect.fromLTWH(rightCx - 11, 86, winW, winH), whitePaint);
    canvas.drawRect(Rect.fromLTWH(rightCx + 6, 86, winW, winH), whitePaint);
    canvas.drawRect(Rect.fromLTWH(rightCx - 11, 98, winW, winH), whitePaint);
    canvas.drawRect(Rect.fromLTWH(rightCx + 6, 98, winW, winH), whitePaint);
    // Door
    canvas.drawRect(Rect.fromLTWH(rightCx - 3.5, 104, 7, 11), whitePaint);
  }

  void _drawPinWithWifi(Canvas canvas, Offset center, Paint pinPaint, Paint wifiPaint) {
    // Teardrop pin outline
    final path = Path()
      ..moveTo(center.dx, center.dy + 20)
      ..cubicTo(
        center.dx - 18,
        center.dy + 8,
        center.dx - 18,
        center.dy - 16,
        center.dx,
        center.dy - 16,
      )
      ..cubicTo(
        center.dx + 18,
        center.dy - 16,
        center.dx + 18,
        center.dy + 8,
        center.dx,
        center.dy + 20,
      );
    canvas.drawPath(path, pinPaint);

    // Wi-Fi radiating arcs inside pin
    final arcPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Small dot at origin
    canvas.drawCircle(Offset(center.dx, center.dy + 7), 1.8, dotPaint);

    // Inner arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(center.dx, center.dy + 7), radius: 6),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      arcPaint,
    );

    // Outer arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(center.dx, center.dy + 7), radius: 11),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LocationWifiPainter old) => old.color != color;
}

/// Step 3: User avatar with glasses and smart scan badge.
class _AccountSmartScanIllustration extends StatelessWidget {
  const _AccountSmartScanIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _AccountSmartScanPainter(color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _AccountSmartScanPainter extends CustomPainter {
  const _AccountSmartScanPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2 - 8;

    // 1. Large circular frame
    canvas.drawCircle(Offset(cx, cy), 50, whitePaint);

    // 2. Avatar head & silhouette
    // Head shape
    canvas.drawCircle(Offset(cx, cy - 8), 20, whitePaint);

    // Hair part/hairline
    final hairPath = Path()
      ..moveTo(cx - 19, cy - 12)
      ..quadraticBezierTo(cx - 8, cy - 26, cx, cy - 24)
      ..quadraticBezierTo(cx + 12, cy - 24, cx + 19, cy - 12);
    canvas.drawPath(hairPath, whitePaint);

    // Eyeglasses
    const glassW = 12.0;
    const glassH = 9.0;
    final leftGlass = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 15, cy - 12, glassW, glassH),
      const Radius.circular(3),
    );
    final rightGlass = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + 3, cy - 12, glassW, glassH),
      const Radius.circular(3),
    );
    canvas.drawRRect(leftGlass, whitePaint);
    canvas.drawRRect(rightGlass, whitePaint);
    // Bridge between glasses
    canvas.drawLine(Offset(cx - 3, cy - 8), Offset(cx + 3, cy - 8), whitePaint);

    // Friendly smile
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy + 2), width: 12, height: 7),
      0,
      math.pi,
      false,
      whitePaint,
    );

    // Shoulders
    final shouldersPath = Path()
      ..moveTo(cx - 32, cy + 38)
      ..quadraticBezierTo(cx - 24, cy + 18, cx - 12, cy + 12)
      ..lineTo(cx + 12, cy + 12)
      ..quadraticBezierTo(cx + 24, cy + 18, cx + 32, cy + 38);
    canvas.drawPath(shouldersPath, whitePaint);

    // 3. Smart Scan Badge at bottom
    final badgeCenter = Offset(cx, cy + 48);
    final badgePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: badgeCenter, width: 34, height: 34),
      const Radius.circular(10),
    );
    canvas.drawRRect(badgeRRect, badgePaint);

    // Smart scan dotted circle inside the blue badge
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const dotCount = 8;
    const radius = 9.0;
    for (var i = 0; i < dotCount; i++) {
      final angle = (i * 2 * math.pi) / dotCount;
      final dotX = badgeCenter.dx + radius * math.cos(angle);
      final dotY = badgeCenter.dy + radius * math.sin(angle);
      final dotSize = (i == 0 || i == 1) ? 2.2 : 1.4;
      canvas.drawCircle(Offset(dotX, dotY), dotSize, dotPaint);
    }
    // Center dot
    canvas.drawCircle(badgeCenter, 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _AccountSmartScanPainter old) => old.color != color;
}

/// Official 4-color Google "G" logo vector painter.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius - 1.5);

    // Red arc (top-left)
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 0.75, math.pi * 0.5, false, redPaint);

    // Yellow arc (bottom-left)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 1.25, math.pi * 0.5, false, yellowPaint);

    // Green arc (bottom)
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 1.75, math.pi * 0.5, false, greenPaint);

    // Blue arc & horizontal crossbar
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi * 0.25, math.pi * 0.35, false, bluePaint);

    // Horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(cx, cy), Offset(cx + radius - 1, cy), barPaint);
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter old) => false;
}
