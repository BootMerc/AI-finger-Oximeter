import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../widgets/ui_components.dart';
import 'main_shell.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  List<ScanResult> _results = [];
  bool _scanning = false;
  bool _connecting = false;
  String _connectingId = '';
  late AnimationController _sonarCtrl;
  late StreamSubscription<List<ScanResult>> _resSub;
  late StreamSubscription<bool> _scanSub;

  @override
  void initState() {
    super.initState();
    _sonarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _resSub = FlutterBluePlus.scanResults.listen((r) => setState(() => _results = r));
    _scanSub = FlutterBluePlus.isScanning.listen((s) => setState(() => _scanning = s));
  }

  @override
  void dispose() {
    _sonarCtrl.dispose();
    _resSub.cancel();
    _scanSub.cancel();
    super.dispose();
  }

  void _startScan() async {
    setState(() => _results = []);
    try { await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15)); }
    catch (e) { debugPrint('Scan error: $e'); }
  }

  void _connect(BluetoothDevice dev) async {
    await FlutterBluePlus.stopScan();
    setState(() { _connecting = true; _connectingId = dev.remoteId.str; });
    try {
      await dev.connect(timeout: const Duration(seconds: 12));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => MainShell(device: dev),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));
    } catch (e) {
      setState(() => _connecting = false);
      debugPrint('Connect error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        Positioned(top: -80, right: -60, child: GlowBlob(color: kPrimary.withOpacity(0.07), size: 280)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                Row(children: [
                  const Icon(Icons.favorite_rounded, color: kRed, size: 22),
                  const SizedBox(width: 10),
                  Text('VitalSense', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.8)),
                ]),
                const SizedBox(height: 4),
                Text('Connect your sensor to begin', style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
                const SizedBox(height: 36),
                _SonarWidget(ctrl: _sonarCtrl, isScanning: _scanning, deviceCount: _results.length),
                const SizedBox(height: 28),
                Expanded(
                  child: _results.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _DeviceCard(
                      result: _results[i],
                      onConnect: _connect,
                      isConnecting: _connecting && _connectingId == _results[i].device.remoteId.str,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ScanButton(isScanning: _scanning, onTap: _startScan),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.bluetooth_searching, color: Colors.white12, size: 56),
      const SizedBox(height: 14),
      Text('No devices found', style: GoogleFonts.inter(color: Colors.white24, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Tap Scan to search nearby', style: GoogleFonts.inter(color: Colors.white12, fontSize: 13)),
    ]),
  );
}

// Internal widgets for ScannerScreen
class _SonarWidget extends StatelessWidget {
  final AnimationController ctrl;
  final bool isScanning;
  final int deviceCount;
  const _SonarWidget({required this.ctrl, required this.isScanning, required this.deviceCount});

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      height: 130, width: 130,
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            if (isScanning) for (int i = 0; i < 3; i++) _ring(((ctrl.value + i * 0.33) % 1.0)),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: kCard,
                border: Border.all(color: isScanning ? kPrimary.withOpacity(0.8) : kCardBorder, width: 2),
                boxShadow: isScanning ? [BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 16)] : [],
              ),
              child: Icon(isScanning ? Icons.bluetooth_searching : Icons.bluetooth, color: isScanning ? kPrimary : Colors.white24, size: 26),
            ),
            if (deviceCount > 0)
              Positioned(
                top: 22, right: 22,
                child: Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: kGreen),
                  child: Center(child: Text('$deviceCount', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _ring(double t) => Transform.scale(
    scale: 0.35 + t * 0.65,
    child: Opacity(
      opacity: (1 - t) * 0.6,
      child: Container(
        width: 120, height: 120,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimary, width: 1.5)),
      ),
    ),
  );
}

class _DeviceCard extends StatelessWidget {
  final ScanResult result;
  final void Function(BluetoothDevice) onConnect;
  final bool isConnecting;
  const _DeviceCard({required this.result, required this.onConnect, required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown Device';
    final isOurs = name == 'VitalSense';
    final rssi = result.rssi;

    return GestureDetector(
      onTap: () => onConnect(result.device),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOurs ? kPrimary.withOpacity(0.06) : kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isOurs ? kPrimary.withOpacity(0.4) : kCardBorder, width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: isOurs ? kPrimary.withOpacity(0.12) : Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(13)),
            child: Icon(isOurs ? Icons.monitor_heart_outlined : Icons.bluetooth, color: isOurs ? kPrimary : Colors.white24, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: isOurs ? Colors.white : Colors.white60))),
                    if (isOurs) ...[const SizedBox(width: 8), _Tag('Your Device', kPrimary)],
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(child: Text(result.device.remoteId.str, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: Colors.white24, fontSize: 11))),
                    const SizedBox(width: 8),
                    _SignalDots(rssi: rssi),
                  ]),
                ]),
          ),
          const SizedBox(width: 12),
          if (isConnecting) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: kPrimary))
          else Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: isOurs ? kPrimary : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(11)),
            child: Text('Connect', style: GoogleFonts.inter(color: isOurs ? Colors.white : Colors.white38, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _SignalDots extends StatelessWidget {
  final int rssi;
  const _SignalDots({required this.rssi});
  @override
  Widget build(BuildContext context) {
    final bars = rssi > -60 ? 3 : rssi > -80 ? 2 : 1;
    return Row(
      children: List.generate(3, (i) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: i < bars ? kGreen : Colors.white12)),
      )),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onTap;
  const _ScanButton({required this.isScanning, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isScanning ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 58,
      decoration: BoxDecoration(
        gradient: isScanning ? null : const LinearGradient(colors: [Color(0xFF00D4FF), Color(0xFF0096CC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        color: isScanning ? kCard : null,
        borderRadius: BorderRadius.circular(17),
        border: isScanning ? Border.all(color: kCardBorder) : null,
        boxShadow: isScanning ? [] : [BoxShadow(color: kPrimary.withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Center(
        child: isScanning
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          const SizedBox(width: 12),
          Text('Scanning...', style: GoogleFonts.inter(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
        ])
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.bluetooth_searching, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text('Scan for Devices', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      ),
    ),
  );
}