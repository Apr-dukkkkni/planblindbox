import 'package:flutter/material.dart';
import 'config/api_config.dart';
import 'data/today_api.dart';
import 'screens/today_page.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlanBlindBoxApp());
}

class PlanBlindBoxApp extends StatefulWidget {
  const PlanBlindBoxApp({super.key});

  @override
  State<PlanBlindBoxApp> createState() => _PlanBlindBoxAppState();
}

class _PlanBlindBoxAppState extends State<PlanBlindBoxApp> {
  late final TodayApi _api = TodayApi(baseUrl: ApiConfig.baseUrl, userId: ApiConfig.userId);

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PlanBlindBox · 每天一点成长',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: TodayPage(api: _api),
      );
}
