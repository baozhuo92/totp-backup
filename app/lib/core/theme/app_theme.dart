import 'package:flutter/material.dart';

/// zolysoft UI 设计规范主题：简约风格、全局简体中文、无 emoji 图标。
/// 品牌色深青 #0F766E（安全/信任感）；提供明暗双模式，跟随系统切换。
class AppTheme {
  AppTheme._();

  /// 品牌主色（深青色）
  static const Color brand = Color(0xFF0F766E);

  // 功能色（zolysoft 规范固定色值）
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color neutral = Color(0xFF6B7280);

  /// 浅色主题
  /// 中性色阶：背景 #F9FAFB / 卡片 #FFFFFF / 边框 #E5E7EB / 主文字 #111827 / 次要 #6B7280
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      surface: const Color(0xFFF9FAFB),
    );
    return _build(scheme, isDark: false);
  }

  /// 暗色主题
  /// 中性色阶：背景 #1F2937 / 卡片 #374151 / 边框 #4B5563 / 主文字 #F9FAFB / 次要 #9CA3AF
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
      surface: const Color(0xFF1F2937),
    );
    return _build(scheme, isDark: true);
  }

  /// 公共主题装配：卡片圆角、输入框样式、按钮最小点击区（zolysoft 无障碍规范 44px）
  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final baseTextColor = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final secondaryTextColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final surfaceColor = isDark ? const Color(0xFF374151) : Colors.white;
    final borderColor = isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
        foregroundColor: baseTextColor,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // zolysoft 表单规范：输入框圆角 4px，边框默认/聚焦/错误三态
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44), // 无障碍最小点击区 44px
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          foregroundColor: brand,
          side: const BorderSide(color: brand),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textTheme: TextTheme(
        // zolysoft 字号阶梯：标题 24/20/16，正文 14，辅助 12
        headlineMedium: TextStyle(fontSize: 24, height: 32 / 24, color: baseTextColor, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 20, height: 28 / 20, color: baseTextColor, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, height: 24 / 16, color: baseTextColor, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(fontSize: 14, height: 22 / 14, color: baseTextColor),
        bodySmall: TextStyle(fontSize: 12, height: 20 / 12, color: secondaryTextColor),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF374151) : const Color(0xFF111827),
      ),
    );
  }
}
