import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import 'dashboard_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'scanner_screen.dart';

class MainShell extends StatefulWidget {
  final BluetoothDevice device;
  const MainShell({super.key, required this.device});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  @override
  void initState() {
    super.initState();
    _connSub = widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ScannerScreen()));
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(device: widget.device),
      const HistoryPage(),
      SettingsPage(device: widget.device, onDisconnect: () {
        widget.device.disconnect();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ScannerScreen()));
      }),
    ];
    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: _BottomNav(current: _tab, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int current;
  final void Function(int) onTap;
  const _BottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: kCard, border: Border(top: BorderSide(color: kCardBorder, width: 1))),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(0, Icons.monitor_heart_outlined, Icons.monitor_heart, 'Dashboard', current, onTap),
            _NavItem(1, Icons.bar_chart_outlined, Icons.bar_chart, 'History', current, onTap),
            _NavItem(2, Icons.settings_outlined, Icons.settings, 'Settings', current, onTap),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final int index, current;
  final IconData icon, activeIcon;
  final String label;
  final void Function(int) onTap;
  const _NavItem(this.index, this.icon, this.activeIcon, this.label, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
        decoration: BoxDecoration(color: active ? kPrimary.withOpacity(0.10) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(active ? activeIcon : icon, color: active ? kPrimary : Colors.white24, size: 24),
          const SizedBox(height: 3),
          Text(label, style: GoogleFonts.inter(color: active ? kPrimary : Colors.white24, fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}