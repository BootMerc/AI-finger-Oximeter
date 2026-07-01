import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../models/app_models.dart';
import '../state/app_state.dart';
import '../widgets/custom_painters.dart';
import '../widgets/ui_components.dart';

class DashboardPage extends StatefulWidget {
  final BluetoothDevice device;
  const DashboardPage({super.key, required this.device});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  // ── BLE characteristic UUIDs ─────────────────────────────────────────────
  static const _SVC    = "19b10000-e8f2-537e-4f6c-d104768a1214";
  static const _BPM    = "19b10001-e8f2-537e-4f6c-d104768a1214";
  static const _FNG    = "19b10004-e8f2-537e-4f6c-d104768a1214";
  static const _SPO2   = "19b10005-e8f2-537e-4f6c-d104768a1214";
  static const _STEP   = "19b10006-e8f2-537e-4f6c-d104768a1214";
  static const _ACT    = "19b10007-e8f2-537e-4f6c-d104768a1214";
  static const _PPG    = "19b10008-e8f2-537e-4f6c-d104768a1214";
  static const _STRESS = "19b10009-e8f2-537e-4f6c-d104768a1214"; // TFLite output

  // ── Vital state ──────────────────────────────────────────────────────────
  String bpm       = "--";
  bool   finger    = false;
  double spo2      = 0;
  int    steps     = 0;
  String activity  = "Still";
  String stress    = "---"; // "Low" | "Moderate" | "High" | "---"

  /// Last 5 stress readings for the trend dots and Rising/Improving indicator.
  final List<String> _stressHistory = [];

  /// Raw IR ring-buffer for the live PPG waveform.
  final List<double> _ppgBuffer = [];
  static const _ppgMaxSamples   = 200;

  final List<StreamSubscription> _charSubs = [];
  late AnimationController _heartCtrl;

  bool _isBpmAlert    = false;
  bool _isSpo2Alert   = false;
  bool _isStressAlert = false;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _discoverServices();
  }

  @override
  void dispose() {
    for (final s in _charSubs) s.cancel();
    _heartCtrl.dispose();
    super.dispose();
  }

  // ── BLE ──────────────────────────────────────────────────────────────────

  void _discoverServices() async {
    try {
      final svcs = await widget.device.discoverServices();
      await Future.delayed(const Duration(milliseconds: 300));

      for (final svc in svcs) {
        if (svc.uuid.toString().toLowerCase() == _SVC) {
          for (final ch in svc.characteristics) {
            try {
              await ch.setNotifyValue(true);
            } catch (e) {
              debugPrint('setNotifyValue failed for ${ch.uuid}: $e');
              continue;
            }
            final uid = ch.uuid.toString().toLowerCase();
            final sub = ch.onValueReceived.listen((val) {
              if (!mounted) return;
              if (val.isNotEmpty) {
                _onValue(uid, utf8.decode(val, allowMalformed: true));
              }
            });
            _charSubs.add(sub);
          }
        }
      }
    } catch (e) {
      debugPrint('Discovery error: $e');
    }
  }

  // ── Value routing ────────────────────────────────────────────────────────

  void _onValue(String uuid, String v) {
    setState(() {
      switch (uuid) {
        case _BPM:
          bpm = v;
          final n = double.tryParse(v);
          if (n != null) {
            _heartCtrl.forward().then((_) => _heartCtrl.reverse());
            if (finger && n > 0) {
              final reading = VitalReading(
                timestamp: DateTime.now(),
                bpm: bpm,
                spo2: spo2,
                steps: steps,
                stress: stress, // included in every history snapshot
              );
              globalHistoryNotifier.value = [
                reading,
                ...globalHistoryNotifier.value,
              ];
              if (globalHistoryNotifier.value.length > 100) {
                globalHistoryNotifier.value.removeLast();
              }
            }
          }
          break;

        case _FNG:
          finger = v == "1";
          if (!finger) {
            bpm = "--";
            _ppgBuffer.clear();
          }
          break;

        case _SPO2:
          spo2 = double.tryParse(v) ?? 0;
          break;

        case _STEP:
          steps = int.tryParse(v) ?? steps;
          break;

        case _ACT:
          activity = v;
          break;

        case _PPG:
          final sample = double.tryParse(v);
          if (sample != null) {
            _ppgBuffer.add(sample);
            if (_ppgBuffer.length > _ppgMaxSamples) {
              _ppgBuffer.removeRange(0, _ppgBuffer.length - _ppgMaxSamples);
            }
          }
          break;

        case _STRESS:
        // Device sends "Low", "Moderate", or "High" every 60 s
          final cleaned = v.trim();
          if (cleaned == "Low" || cleaned == "Moderate" || cleaned == "High") {
            stress = cleaned;
            _stressHistory.add(cleaned);
            if (_stressHistory.length > 5) _stressHistory.removeAt(0);
          }
          break;
      }
    });

    _checkAlerts(double.tryParse(bpm) ?? 0, spo2);
  }

  // ── Alert logic ──────────────────────────────────────────────────────────

  void _checkAlerts(double currentBpm, double currentSpo2) {
    final s = globalSettingsNotifier.value;
    bool triggerVibe = false;

    // BPM
    if (currentBpm > 0 && (currentBpm >= s.bpmHigh || currentBpm <= s.bpmLow)) {
      if (!_isBpmAlert) { _isBpmAlert = true; triggerVibe = true; }
    } else {
      _isBpmAlert = false;
    }

    // SpO2
    if (currentSpo2 > 0 && currentSpo2 <= s.spo2Low) {
      if (!_isSpo2Alert) { _isSpo2Alert = true; triggerVibe = true; }
    } else {
      _isSpo2Alert = false;
    }

    // Stress — only vibrates once per "High" episode, resets when it drops
    if (stress == "High" && s.stressAlert) {
      if (!_isStressAlert) { _isStressAlert = true; triggerVibe = true; }
    } else {
      _isStressAlert = false;
    }

    if (triggerVibe && s.vibration) HapticFeedback.heavyImpact();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Color _stressColor() =>
      stress == "High"     ? kRed    :
      stress == "Moderate" ? kOrange :
      stress == "Low"      ? kGreen  : Colors.white24;

  Color _spo2Color() =>
      spo2 >= 95 ? kGreen : spo2 >= 90 ? kOrange : kRed;

  IconData _actIcon() =>
      activity == "Running" ? Icons.directions_run :
      activity == "Walking" ? Icons.directions_walk :
      Icons.self_improvement;

  String _bpmStatusText() {
    final v = double.tryParse(bpm) ?? 0;
    if (v == 0) return '';
    if (v < 60)  return 'Below resting range';
    if (v <= 100) return 'Normal resting range';
    if (v <= 140) return 'Elevated';
    return 'High — rest recommended';
  }

  Color _bpmStatusColor() {
    final v = double.tryParse(bpm) ?? 0;
    if (v < 60 || (v > 100 && v <= 140)) return kOrange;
    if (v > 140) return kRed;
    return kGreen;
  }

  String _fmt(int n) =>
      n >= 1000 ? "${(n / 1000).toStringAsFixed(1)}k" : "$n";

  // ── Wellness Score (0–100) ── surprise feature ───────────────────────────
  //
  // Composite score derived from all three sensor streams in real time:
  //   BPM health   → 0–40 pts   (optimal zone 60–80 BPM)
  //   SpO2 health  → 0–35 pts   (optimal ≥ 98%)
  //   Stress level → 0–25 pts   (Low = full marks, High = 0)
  //
  Map<String, int> _wellnessBreakdown() {
    // BPM component
    final bpmVal = double.tryParse(bpm) ?? 0;
    int bpmScore;
    if (bpmVal <= 0) {
      bpmScore = 20; // unknown → neutral half score
    } else if (bpmVal >= 60 && bpmVal <= 80) {
      bpmScore = 40;
    } else if ((bpmVal >= 50 && bpmVal < 60) || (bpmVal > 80 && bpmVal <= 100)) {
      bpmScore = 28;
    } else if ((bpmVal >= 40 && bpmVal < 50) || (bpmVal > 100 && bpmVal <= 120)) {
      bpmScore = 15;
    } else {
      bpmScore = 5;
    }

    // SpO2 component
    int spo2Score;
    if (spo2 <= 0) {
      spo2Score = 17;
    } else if (spo2 >= 98) {
      spo2Score = 35;
    } else if (spo2 >= 95) {
      spo2Score = 28;
    } else if (spo2 >= 92) {
      spo2Score = 18;
    } else if (spo2 >= 88) {
      spo2Score = 8;
    } else {
      spo2Score = 2;
    }

    // Stress component
    final stressScore = stress == "Low"      ? 25 :
    stress == "Moderate" ? 14 :
    stress == "High"     ? 0  : 12; // "---" → neutral

    return {'bpm': bpmScore, 'spo2': spo2Score, 'stress': stressScore};
  }

  int _totalWellness() {
    final b = _wellnessBreakdown();
    return (b['bpm']! + b['spo2']! + b['stress']!).clamp(0, 100);
  }

  // ── UI build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(
      child: ValueListenableBuilder<UserSettings>(
        valueListenable: globalSettingsNotifier,
        builder: (context, settings, _) {
          return CustomScrollView(slivers: [
            _header(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _statusBanner(),
                  const SizedBox(height: 18),
                  _wellnessCard(),          // ← SURPRISE: wellness score
                  const SizedBox(height: 14),
                  _bpmCard(),
                  const SizedBox(height: 14),
                  Row(children: [
                    if (settings.showSpo2) ...[
                      Expanded(child: _spo2Card()),
                      const SizedBox(width: 14),
                    ],
                    Expanded(child: _activityCard()),
                  ]),
                  if (settings.showStress) ...[
                    const SizedBox(height: 14),
                    _stressCard(),
                  ],
                  const SizedBox(height: 14),
                  if (settings.showSteps) _stepsCard(),
                ]),
              ),
            ),
          ]);
        },
      ),
    ),
  );

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _header() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dashboard',
                style: GoogleFonts.inter(
                    fontSize: 26, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: -0.5)),
            Text('Live sensor data',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: kGreen.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGreen.withOpacity(0.3))),
            child: Row(children: [
              Container(width: 7, height: 7,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: kGreen)),
              const SizedBox(width: 6),
              Text('Connected',
                  style: GoogleFonts.inter(
                      color: kGreen, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    ),
  );

  // ── Status banner ─────────────────────────────────────────────────────────

  Widget _statusBanner() => AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: finger ? kGreen.withOpacity(0.07) : kOrange.withOpacity(0.07),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
          color: finger ? kGreen.withOpacity(0.3) : kOrange.withOpacity(0.3)),
    ),
    child: Row(children: [
      Icon(finger ? Icons.fingerprint : Icons.touch_app_outlined,
          color: finger ? kGreen : kOrange, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
            finger
                ? "Sensor active — measuring all vitals"
                : "Place your finger on the MAX30102 sensor",
            style: GoogleFonts.inter(
                color: finger ? kGreen : kOrange,
                fontWeight: FontWeight.w500, fontSize: 13)),
      ),
    ]),
  );

  // ── Wellness Score card (SURPRISE FEATURE) ────────────────────────────────
  //
  // Fuses BPM, SpO2 and AI stress level into one 0-100 wellness score shown
  // as an animated 270° arc gauge. The arc, score colour, and breakdown bars
  // all update in real time as new BLE values arrive.

  Widget _wellnessCard() {
    final breakdown = _wellnessBreakdown();
    final score = _totalWellness();
    final color = score >= 80 ? kGreen : score >= 55 ? kOrange : kRed;
    final label = score >= 80 ? "Excellent" : score >= 55 ? "Fair" : "Needs Attention";

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: score / 100.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, animVal, __) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kCard, Color.lerp(kCard, color, 0.07)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Arc gauge
              SizedBox(
                width: 100, height: 100,
                child: CustomPaint(
                  painter: WellnessGaugePainter(progress: animVal, color: color),
                  child: Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$score',
                          style: GoogleFonts.inter(
                              fontSize: 30, fontWeight: FontWeight.w900,
                              color: Colors.white, height: 1.0)),
                      Text('/100',
                          style: GoogleFonts.inter(fontSize: 9, color: Colors.white24)),
                    ],
                  )),
                ),
              ),
              const SizedBox(width: 20),
              // Label + breakdown bars
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wellness Score',
                      style: GoogleFonts.inter(
                          color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(label,
                      style: GoogleFonts.inter(
                          color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _miniBar('Heart',  breakdown['bpm']!,    40, kRed),
                  const SizedBox(height: 5),
                  _miniBar('Oxygen', breakdown['spo2']!,   35, kPrimary),
                  const SizedBox(height: 5),
                  _miniBar('Stress', breakdown['stress']!, 25, kPurple),
                ],
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _miniBar(String label, int value, int max, Color color) => Row(children: [
    SizedBox(width: 46,
        child: Text(label,
            style: GoogleFonts.inter(color: Colors.white30, fontSize: 10))),
    Expanded(child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value / max,
        minHeight: 4,
        backgroundColor: color.withOpacity(0.10),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    )),
    const SizedBox(width: 6),
    Text('$value',
        style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
  ]);

  // ── BPM card with live PPG waveform ──────────────────────────────────────

  Widget _bpmCard() {
    final hasPPG = _ppgBuffer.length > 5 && finger;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12082E), Color(0xFF090518)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2D1060).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
              color: kPurple.withOpacity(0.15),
              blurRadius: 32,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, hasPPG ? 12 : 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.5).animate(
                          CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut)),
                      child: const Icon(Icons.favorite_rounded, color: kRed, size: 22),
                    ),
                    const SizedBox(width: 8),
                    Text('Heart Rate',
                        style: GoogleFonts.inter(
                            color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500)),
                  ]),
                ],
              ),
              const SizedBox(height: 14),
              // BPM value
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(bpm,
                    style: GoogleFonts.inter(
                      fontSize: 76, fontWeight: FontWeight.w800,
                      color: Colors.white, height: 1,
                      shadows: [Shadow(color: kPurple.withOpacity(0.6), blurRadius: 24)],
                    )),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 8),
                  child: Text('BPM',
                      style: GoogleFonts.inter(
                          fontSize: 20, color: Colors.white30, fontWeight: FontWeight.w500)),
                ),
              ]),
              // Status sub-label
              if (bpm != "--" && _bpmStatusText().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _bpmStatusColor())),
                  const SizedBox(width: 6),
                  Text(_bpmStatusText(),
                      style: GoogleFonts.inter(
                          color: _bpmStatusColor(), fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ],
            ]),
          ),

          // Live PPG waveform — was prepared but never placed in the original
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: hasPPG
                ? ClipRRect(
              key: const ValueKey('ppg'),
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24)),
              child: SizedBox(
                height: 68,
                width: double.infinity,
                child: CustomPaint(
                  painter: SparklinePainter(
                      List<double>.from(_ppgBuffer),
                      kPurple.withOpacity(0.75)),
                ),
              ),
            )
                : const SizedBox(key: ValueKey('noppg')),
          ),
        ],
      ),
    );
  }

  // ── Stress card ───────────────────────────────────────────────────────────

  Widget _stressCard() {
    final col   = _stressColor();
    final isHigh = stress == "High";

    return GestureDetector(
      // Tap anywhere on the stress card when High → open breathing guide
      onTap: isHigh
          ? () => showDialog(
          context: context,
          builder: (_) => const _BreathingGuideDialog())
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [col.withOpacity(0.10), kCard],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: col.withOpacity(0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 33, height: 33,
                  decoration: BoxDecoration(
                      color: col.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.psychology_outlined, color: col, size: 16),
                ),
                const SizedBox(width: 10),
                Text('Stress Level',
                    style: GoogleFonts.inter(
                        color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
              if (_stressHistory.length >= 2) _stressTrendBadge(),
            ],
          ),
          const SizedBox(height: 14),

          // Stress value + breathe button
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(stress,
                style: GoogleFonts.inter(
                    fontSize: stress.length > 8 ? 24 : 32,
                    fontWeight: FontWeight.w800,
                    color: col, height: 1.0)),
            const Spacer(),
            if (isHigh)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPrimary.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.air_rounded, color: kPrimary, size: 14),
                  const SizedBox(width: 5),
                  Text('Breathe',
                      style: GoogleFonts.inter(
                          color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),

          // Sub-label
          const SizedBox(height: 6),
          Text(
            stress == "Low"      ? "HRV indicates relaxed autonomic state"   :
            stress == "Moderate" ? "Mild cognitive load detected"             :
            stress == "High"     ? "Tap to start a breathing exercise"        :
            "Awaiting first inference — ~60 s",
            style: GoogleFonts.inter(
                color: col.withOpacity(0.70), fontSize: 12, fontWeight: FontWeight.w500),
          ),

          // Recent readings — colour-coded dots
          if (_stressHistory.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Text('Recent  ',
                  style: GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
              ..._stressHistory.reversed.take(5).map((s) {
                final c = s == "High" ? kRed : s == "Moderate" ? kOrange : kGreen;
                return Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                );
              }),
            ]),
          ],
        ]),
      ),
    );
  }

  /// Rising / Improving / Stable badge based on last two readings.
  Widget _stressTrendBadge() {
    int enc(String s) => s == "High" ? 2 : s == "Moderate" ? 1 : 0;
    final diff = enc(_stressHistory.last) -
        enc(_stressHistory[_stressHistory.length - 2]);
    final icon  = diff > 0 ? Icons.arrow_upward_rounded
        : diff < 0 ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;
    final color = diff > 0 ? kRed : diff < 0 ? kGreen : Colors.white38;
    final label = diff > 0 ? "Rising" : diff < 0 ? "Improving" : "Stable";

    return Row(children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 3),
      Text(label,
          style: GoogleFonts.inter(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }

  // ── Other metric cards ────────────────────────────────────────────────────

  Widget _spo2Card() => MetricCard(
    label: 'Blood Oxygen',
    value: spo2 > 0 ? "${spo2.toStringAsFixed(1)}%" : "--",
    unit: 'SpO₂',
    icon: Icons.water_drop_outlined,
    color: _spo2Color(),
    status: spo2 > 0
        ? (spo2 >= 95 ? "Normal" : spo2 >= 90 ? "Low" : "Critical")
        : null,
  );

  Widget _stepsCard() => MetricCard(
    label: 'Steps Today',
    value: _fmt(steps),
    unit: 'MPU6050',
    icon: Icons.directions_walk_outlined,
    color: kPrimary,
    status: steps > 0 ? '${(steps * 0.00075).toStringAsFixed(2)} km' : null,
  );

  Widget _activityCard() => MetricCard(
    label: 'Activity',
    value: activity,
    unit: 'MPU6050',
    icon: _actIcon(),
    color: kPurple,
    status: activity == "Running" ? "High intensity"
        : activity == "Walking" ? "Active"
        : "Resting",
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Breathing Guide Dialog — opens when user taps the stress card while High.
//
// Implements 4-4-4-4 box breathing (inhale → hold → exhale → hold), a
// clinically validated technique for rapid HRV recovery. An animated circle
// expands and contracts to give the user a visual pacer; the phase label and
// countdown timer update every second.
// ══════════════════════════════════════════════════════════════════════════════

class _BreathingGuideDialog extends StatefulWidget {
  const _BreathingGuideDialog();
  @override
  State<_BreathingGuideDialog> createState() => _BreathingGuideDialogState();
}

class _BreathingGuideDialogState extends State<_BreathingGuideDialog>
    with SingleTickerProviderStateMixin {

  static const _phaseNames = ['Inhale', 'Hold', 'Exhale', 'Hold'];
  // Seconds for each phase — box breathing: 4-4-4-4
  static const _phaseDurations = [4, 4, 4, 4];

  late AnimationController _ctrl;
  late Animation<double> _scale;

  int _phase      = 0;
  int _countdown  = 4;
  int _cycles     = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _beginPhase();
  }

  void _beginPhase() {
    _ticker?.cancel();
    _countdown = _phaseDurations[_phase];

    // Inhale → expand, Exhale → contract, Hold → freeze
    if (_phase == 0) {
      _ctrl.forward(from: _ctrl.value);
    } else if (_phase == 2) {
      _ctrl.reverse(from: _ctrl.value);
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _countdown--; });
      if (_countdown <= 0) {
        t.cancel();
        _phase = (_phase + 1) % 4;
        if (_phase == 0) _cycles++;
        _beginPhase();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phaseColor = _phase == 0 ? kPrimary
        : _phase == 2 ? kPurple
        : kGreen;

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          Text('Breathing Exercise',
              style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Box breathing  ·  4-4-4-4',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),

          const SizedBox(height: 32),

          // Animated breathing circle
          AnimatedBuilder(
            animation: _scale,
            builder: (_, __) {
              final sz = 80.0 + _scale.value * 56.0;
              return Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: phaseColor.withOpacity(0.25), width: 1.5)),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: sz, height: sz,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: phaseColor.withOpacity(0.14),
                      boxShadow: [
                        BoxShadow(
                            color: phaseColor.withOpacity(0.30),
                            blurRadius: 24,
                            spreadRadius: 4)
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 26),

          // Phase label + countdown
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(_phaseNames[_phase],
                key: ValueKey(_phase),
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text('$_countdown s',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 6),
          Text(_cycles == 0 ? 'First cycle' : '$_cycles ${_cycles == 1 ? "cycle" : "cycles"} completed',
              style: GoogleFonts.inter(color: Colors.white24, fontSize: 12)),

          const SizedBox(height: 28),

          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kPrimary.withOpacity(0.3))),
              child: Center(
                child: Text('Done',
                    style: GoogleFonts.inter(
                        color: kPrimary, fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}