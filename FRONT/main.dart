import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/colors.dart';
import 'models/app_models.dart';
import 'state/app_state.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final p = await SharedPreferences.getInstance();
  globalSettingsNotifier.value = UserSettings(
    bpmHigh: p.getInt('bpmHigh') ?? 130,
    bpmLow: p.getInt('bpmLow') ?? 50,
    spo2Low: p.getDouble('spo2Low') ?? 92.0,
    showSpo2: p.getBool('showSpo2') ?? true,
    showSteps: p.getBool('showSteps') ?? true,
    vibration: p.getBool('vibration') ?? true,
  );

  runApp(const VitalSenseApp());
}

class VitalSenseApp extends StatelessWidget {
  const VitalSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitalSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        primaryColor: kPrimary,
        colorScheme: const ColorScheme.dark(
          primary: kPrimary,
          secondary: kPurple,
          surface: kCard,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}