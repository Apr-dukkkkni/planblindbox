import 'package:flutter/material.dart';

class AppColors {
  static const canvas = Color(0xFFF7F8F3);
  static const forest = Color(0xFF25493E);
  static const deepForest = Color(0xFF193B32);
  static const leaf = Color(0xFF6B9A79);
  static const paleGreen = Color(0xFFE5F0E5);
  static const ink = Color(0xFF23392E);
  static const muted = Color(0xFF78877B);
  static const amber = Color(0xFFEFAE5F);
  static const paleAmber = Color(0xFFFFF2DB);
  static const rose = Color(0xFFC6514A);
  static const paleRose = Color(0xFFFFECE9);
  static const border = Color(0xFFEBEEE6);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.forest,
      brightness: Brightness.light, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC'],
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.canvas, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7F8F5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border)),
    ),
  );
}
