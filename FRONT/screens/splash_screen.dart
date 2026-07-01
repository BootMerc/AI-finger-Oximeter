import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../widgets/custom_painters.dart';
import '../widgets/ui_components.dart';
import 'scanner_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _ecgCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ecgCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 20, end: 0).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 900), () { if (mounted) _fadeCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, __, ___) => const ScannerScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _ecgCtrl.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          Positioned(top: -100, left: -80, child: GlowBlob(color: kPrimary.withOpacity(0.12), size: 350)),
          Positioned(bottom: -60, right: -100, child: GlowBlob(color: kPurple.withOpacity(0.10), size: 300)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300, height: 90,
                  child: AnimatedBuilder(
                    animation: _ecgCtrl,
                    builder: (_, __) => CustomPaint(painter: ECGPainter(progress: _ecgCtrl.value, color: kPrimary)),
                  ),
                ),
                const SizedBox(height: 44),
                AnimatedBuilder(
                  animation: _fadeAnim,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnim.value,
                    child: Transform.translate(offset: Offset(0, _slideAnim.value), child: child),
                  ),
                  child: Column(children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Transform.scale(
                        scale: 1.0 + _pulseCtrl.value * 0.12,
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [kRed.withOpacity(0.3), Colors.transparent]),
                          ),
                          child: const Icon(Icons.favorite_rounded, color: kRed, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('VitalSense', style: GoogleFonts.inter(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.2)),
                    const SizedBox(height: 6),
                    Text('Real-time Health Monitoring', style: GoogleFonts.inter(fontSize: 14, color: Colors.white38, letterSpacing: 0.4)),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _SensorChip('MAX30102'), SizedBox(width: 8),
                        _SensorChip('MPU6050'), SizedBox(width: 8),
                        _SensorChip('ESP32-S3'),
                      ],
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorChip extends StatelessWidget {
  final String label;
  const _SensorChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: kPrimary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kPrimary.withOpacity(0.25)),
    ),
    child: Text(label, style: GoogleFonts.inter(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}