
import 'package:flutter/material.dart';
import 'config/api_config.dart';
import 'data/today_api.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';

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
  late final TodayApi _api = TodayApi(
    baseUrl: ApiConfig.baseUrl,
    userId: ApiConfig.userId,
  );

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlanBlindBox · 每天一点成长',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 600;

          final appHeight = constraints.maxHeight > 860
              ? 860.0
              : constraints.maxHeight;

          return ColoredBox(
            color: isDesktop
                ? const Color(0xFFEFF2EF)
                : Colors.white,
            child: Center(
              child: Container(
                width: isDesktop ? 430 : constraints.maxWidth,
                height: isDesktop
                    ? appHeight
                    : constraints.maxHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    isDesktop ? 24 : 0,
                  ),
                  boxShadow: isDesktop
                      ? const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ]
                      : const [],
                ),
                // 注意：使用已经定义好的 _api
                child: AppShell(api: _api),
              ),
            ),
          );
        },
      ),
    );
  }
}
