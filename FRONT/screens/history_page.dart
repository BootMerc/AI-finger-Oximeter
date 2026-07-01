import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../models/app_models.dart';
import '../state/app_state.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History',
                      style: GoogleFonts.inter(
                          fontSize: 26, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5)),
                  Text('Session readings',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<VitalReading>>(
                valueListenable: globalHistoryNotifier,
                builder: (context, history, _) {
                  if (history.isEmpty) return _buildEmptyState();

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = history[index];
                      final h = record.timestamp.hour;
                      final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
                      final amPm   = h >= 12 ? "PM" : "AM";
                      final time   =
                          "$hour12:${record.timestamp.minute.toString().padLeft(2, '0')}"
                          ":${record.timestamp.second.toString().padLeft(2, '0')} $amPm";

                      // Stress colour for badge
                      final stressColor = record.stress == "High"     ? kRed
                          : record.stress == "Moderate" ? kOrange
                          : kGreen;
                      final hasStress = record.stress != "---";

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kCardBorder)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left: time + BPM
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(time,
                                      style: GoogleFonts.inter(
                                          color: Colors.white38, fontSize: 11)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    const Icon(Icons.favorite, color: kRed, size: 14),
                                    const SizedBox(width: 4),
                                    Text('${record.bpm} BPM',
                                        style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                                ],
                              ),
                            ),

                            // Right: Steps + SpO2 + stress badge
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${record.steps} Steps',
                                    style: GoogleFonts.inter(
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                const SizedBox(height: 3),
                                Text('SpO₂: ${record.spo2.toStringAsFixed(1)}%',
                                    style: GoogleFonts.inter(
                                        color: Colors.white70, fontSize: 13)),
                                // Stress badge — only shown when a reading exists
                                if (hasStress) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: stressColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: stressColor.withOpacity(0.25))),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.psychology_outlined,
                                          color: stressColor, size: 11),
                                      const SizedBox(width: 4),
                                      Text(record.stress,
                                          style: GoogleFonts.inter(
                                              color: stressColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: kCard, shape: BoxShape.circle,
                border: Border.all(color: kCardBorder)),
            child: const Icon(Icons.bar_chart_outlined,
                color: Colors.white12, size: 34),
          ),
          const SizedBox(height: 18),
          Text('No readings yet',
              style: GoogleFonts.inter(
                  color: Colors.white30, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Connect and start measuring to\nrecord your health history',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}