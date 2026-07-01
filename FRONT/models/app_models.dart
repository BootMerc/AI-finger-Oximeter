class VitalReading {
  final DateTime timestamp;
  final String bpm;
  final double spo2;
  final int steps;
  final String stress; // "Low" | "Moderate" | "High" | "---"

  VitalReading({
    required this.timestamp,
    required this.bpm,
    required this.spo2,
    required this.steps,
    this.stress = "---", // default keeps existing call-sites intact
  });
}

class UserSettings {
  final int bpmHigh;
  final int bpmLow;
  final double spo2Low;
  final bool showSpo2;
  final bool showSteps;
  final bool showStress;   // toggle stress card on dashboard
  final bool vibration;
  final bool stressAlert;  // haptic on High stress detection

  UserSettings({
    this.bpmHigh     = 130,
    this.bpmLow      = 50,
    this.spo2Low     = 92.0,
    this.showSpo2    = true,
    this.showSteps   = true,
    this.showStress  = true,
    this.vibration   = true,
    this.stressAlert = true,
  });
}