import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/colors.dart';
import '../models/app_models.dart';
import '../state/app_state.dart';

class SettingsPage extends StatefulWidget {
  final BluetoothDevice device;
  final VoidCallback onDisconnect;
  const SettingsPage({super.key, required this.device, required this.onDisconnect});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String userName = "User";
  int userAge = 25;
  double userWeight = 70.0;
  int bpmHigh = 130;
  int bpmLow = 50;
  double spo2Low = 92.0;
  bool showSpo2 = true;
  bool showSteps = true;
  bool vibration = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      userName   = p.getString('name') ?? 'User';
      userAge    = p.getInt('age') ?? 25;
      userWeight = p.getDouble('weight') ?? 70.0;
      bpmHigh    = p.getInt('bpmHigh') ?? 130;
      bpmLow     = p.getInt('bpmLow') ?? 50;
      spo2Low    = p.getDouble('spo2Low') ?? 92.0;
      showSpo2   = p.getBool('showSpo2') ?? true;
      showSteps  = p.getBool('showSteps') ?? true;
      vibration  = p.getBool('vibration') ?? true;
    });
  }

  void _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('name', userName);
    await p.setInt('age', userAge);
    await p.setDouble('weight', userWeight);
    await p.setInt('bpmHigh', bpmHigh);
    await p.setInt('bpmLow', bpmLow);
    await p.setDouble('spo2Low', spo2Low);
    await p.setBool('showSpo2', showSpo2);
    await p.setBool('showSteps', showSteps);
    await p.setBool('vibration', vibration);

    globalSettingsNotifier.value = UserSettings(
      bpmHigh: bpmHigh, bpmLow: bpmLow, spo2Low: spo2Low,
      showSpo2: showSpo2, showSteps: showSteps, vibration: vibration,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                Text('Customize VitalSense', style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _section('Profile'), _profileCard(), const SizedBox(height: 24),
              _section('Alert Thresholds'), _thresholdCard(), const SizedBox(height: 24),
              _section('Display'),
              _toggleCard([
                _ToggleItem('Show SpO₂', 'Blood oxygen on dashboard', Icons.water_drop_outlined, showSpo2, (v) => setState(() { showSpo2 = v; _save(); })),
                _ToggleItem('Show Steps', 'Step counter on dashboard', Icons.directions_walk_outlined, showSteps, (v) => setState(() { showSteps = v; _save(); })),
              ]),
              const SizedBox(height: 24),
              _section('Notifications'),
              _toggleCard([
                _ToggleItem('Vibration Alerts', 'Vibrate at threshold alerts', Icons.vibration, vibration, (v) => setState(() { vibration = v; _save(); })),
              ]),
              const SizedBox(height: 24),
              _section('Device'), _deviceCard(), const SizedBox(height: 24),
              _section('About'), _aboutCard(), const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    ),
  );

  Widget _section(String t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t.toUpperCase(), style: GoogleFonts.inter(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0)));

  Widget _profileCard() => _Card(child: Column(children: [
    Row(children: [
      Container(
        width: 54, height: 54,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPurple], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => _strDialog('Name', userName, (v) => setState(() { userName = v; _save(); })),
            child: Row(children: [
              Text(userName, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.2), size: 15),
            ]),
          ),
          Text('Age $userAge • ${userWeight.toStringAsFixed(0)} kg', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
        ]),
      ),
    ]),
    const SizedBox(height: 16), const Divider(color: kCardBorder, height: 1), const SizedBox(height: 14),
    Row(children: [
      Expanded(child: _TapTile(label: 'Age', value: '$userAge yrs', onTap: () => _intDialog('Age', userAge, 5, 120, (v) => setState(() { userAge = v; _save(); })))),
      const SizedBox(width: 12),
      Expanded(child: _TapTile(label: 'Weight', value: '${userWeight.toStringAsFixed(0)} kg', onTap: () => _dblDialog('Weight (kg)', userWeight, 20, 250, (v) => setState(() { userWeight = v; _save(); })))),
    ]),
  ]));

  Widget _thresholdCard() => _Card(child: Column(children: [
    _Slider('BPM High Alert', bpmHigh.toDouble(), 90, 200, kRed, '$bpmHigh BPM', (v) => setState(() { bpmHigh = v.round(); _save(); })), const SizedBox(height: 8),
    _Slider('BPM Low Alert', bpmLow.toDouble(), 30, 75, kOrange, '$bpmLow BPM', (v) => setState(() { bpmLow = v.round(); _save(); })), const SizedBox(height: 8),
    _Slider('SpO₂ Low Alert', spo2Low, 80, 97, kPrimary, '${spo2Low.toStringAsFixed(0)}%', (v) => setState(() { spo2Low = v; _save(); })),
  ]));

  Widget _toggleCard(List<_ToggleItem> items) => _Card(
    child: Column(
      children: items.asMap().entries.map((e) {
        final it = e.value; final isLast = e.key == items.length - 1;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: kPrimary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)), child: Icon(it.icon, color: kPrimary, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(it.subtitle, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
              ])),
              Switch.adaptive(value: it.value, onChanged: it.onChanged, activeColor: kPrimary, activeTrackColor: kPrimary.withOpacity(0.3)),
            ]),
          ),
          if (!isLast) const Divider(color: kCardBorder, height: 1),
        ]);
      }).toList(),
    ),
  );

  Widget _deviceCard() => _Card(child: Column(children: [
    _InfoRow(Icons.bluetooth, 'Device', widget.device.platformName), const Divider(color: kCardBorder, height: 20),
    _InfoRow(Icons.memory, 'Hardware', 'ESP32-S3'), const Divider(color: kCardBorder, height: 20),
    _InfoRow(Icons.sensors, 'Sensors', 'MAX30102 · MPU6050'), const Divider(color: kCardBorder, height: 20),
    GestureDetector(
      onTap: widget.onDisconnect,
      child: Container(
        height: 46, decoration: BoxDecoration(color: kRed.withOpacity(0.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: kRed.withOpacity(0.3))),
        child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.bluetooth_disabled, color: kRed, size: 18), const SizedBox(width: 8), Text('Disconnect Device', style: GoogleFonts.inter(color: kRed, fontWeight: FontWeight.w600, fontSize: 14))])),
      ),
    ),
  ]));

  Widget _aboutCard() => _Card(child: Column(children: [
    _AboutRow('App', 'VitalSense v1.0'), const Divider(color: kCardBorder, height: 20),
    _AboutRow('Protocol', 'BLE GATT'), const Divider(color: kCardBorder, height: 20),
    _AboutRow('Framework', 'Flutter'),
  ]));

  void _strDialog(String lbl, String cur, Function(String) save) {
    final c = TextEditingController(text: cur);
    showDialog(context: context, builder: (_) => _StyledDialog(
      title: 'Edit $lbl',
      content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: Colors.white.withOpacity(0.06), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      onConfirm: () { save(c.text); Navigator.pop(context); },
    ));
  }
  void _intDialog(String lbl, int cur, int mn, int mx, Function(int) save) {
    int tmp = cur;
    showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (ctx, set) => _StyledDialog(
        title: 'Set $lbl',
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$tmp', style: GoogleFonts.inter(color: kPrimary, fontSize: 36, fontWeight: FontWeight.w800)),
          Slider(value: tmp.toDouble(), min: mn.toDouble(), max: mx.toDouble(), divisions: mx - mn, activeColor: kPrimary, onChanged: (v) => set(() => tmp = v.round())),
        ]),
        onConfirm: () { save(tmp); Navigator.pop(context); },
      ),
    ));
  }
  void _dblDialog(String lbl, double cur, double mn, double mx, Function(double) save) {
    double tmp = cur;
    showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (ctx, set) => _StyledDialog(
        title: 'Set $lbl',
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tmp.toStringAsFixed(1), style: GoogleFonts.inter(color: kPrimary, fontSize: 36, fontWeight: FontWeight.w800)),
          Slider(value: tmp, min: mn, max: mx, activeColor: kPrimary, onChanged: (v) => set(() => tmp = double.parse(v.toStringAsFixed(1)))),
        ]),
        onConfirm: () { save(tmp); Navigator.pop(context); },
      ),
    ));
  }
}

// Internal reusable widgets for SettingsPage
class _ToggleItem { final String title, subtitle; final IconData icon; final bool value; final ValueChanged<bool> onChanged; const _ToggleItem(this.title, this.subtitle, this.icon, this.value, this.onChanged); }
class _Card extends StatelessWidget { final Widget child; const _Card({required this.child}); @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kCardBorder)), child: child); }
class _TapTile extends StatelessWidget {
  final String label, value; final VoidCallback onTap; const _TapTile({required this.label, required this.value, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: GoogleFonts.inter(color: Colors.white30, fontSize: 11)), const SizedBox(height: 2), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2), size: 16)])])),
  );
}
class _Slider extends StatelessWidget {
  final String label; final double value, min, max; final Color color; final String display; final ValueChanged<double> onChanged; const _Slider(this.label, this.value, this.min, this.max, this.color, this.display, this.onChanged);
  @override Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text(display, style: GoogleFonts.inter(color: color, fontSize: 12, fontWeight: FontWeight.w700)))]),
    SliderTheme(data: SliderThemeData(activeTrackColor: color, inactiveTrackColor: color.withOpacity(0.12), thumbColor: color, overlayColor: color.withOpacity(0.10), trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8)), child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
  ],
  );
}
class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value; const _InfoRow(this.icon, this.label, this.value);
  @override Widget build(BuildContext context) => Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: kPrimary.withOpacity(0.09), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: kPrimary, size: 17)), const SizedBox(width: 12), Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)), const Spacer(), Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))]);
}
class _AboutRow extends StatelessWidget {
  final String label, value; const _AboutRow(this.label, this.value);
  @override Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)), Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))]);
}
class _StyledDialog extends StatelessWidget {
  final String title; final Widget content; final VoidCallback onConfirm; const _StyledDialog({required this.title, required this.content, required this.onConfirm});
  @override Widget build(BuildContext context) => AlertDialog(backgroundColor: kCard, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), title: Text(title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)), content: content, actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white38))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: onConfirm, child: const Text('Save'))]);
}