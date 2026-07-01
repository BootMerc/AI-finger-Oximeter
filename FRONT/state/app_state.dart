import 'package:flutter/material.dart';
import '../models/app_models.dart';

final ValueNotifier<UserSettings> globalSettingsNotifier = ValueNotifier(UserSettings());
final ValueNotifier<List<VitalReading>> globalHistoryNotifier = ValueNotifier([]);