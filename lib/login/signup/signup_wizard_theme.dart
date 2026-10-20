import 'package:flutter/material.dart';

/// Shared colours and text styles for the sign-up wizard.
///
/// These match the palette the login screen already hands to `FlutterLogin`
/// (`pageColorLight` / `accentColor`) so the wizard reads as a continuation of
/// that screen rather than a different app.
class SignupWizardTheme {
  static const Color background = Color(0xFF082D38);
  static const Color surface = Color(0xFF0E3D4A);
  static const Color accent = Colors.amber;
  static const Color highlight = Color(0xFFff673a);

  static const TextStyle title = TextStyle(
    color: Colors.white,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle body = TextStyle(
    color: Colors.white70,
    fontSize: 15,
    height: 1.4,
  );

  /// Dark-field input decoration used by every text field in the wizard.
  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      helperStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF8A80)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF8A80), width: 2),
      ),
    );
  }

  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: background,
        disabledBackgroundColor: Colors.white24,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );

  /// [primaryButton] sized to its label rather than the full width.
  ///
  /// The full-width bar is right for a form's call to action, but wrong on top
  /// of a map: it reaches the right-hand edge and covers Google's zoom
  /// controls. Same colours, same height — it just stops stretching.
  static ButtonStyle get primaryButtonCompact => primaryButton.copyWith(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 52)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 24),
        ),
      );

  static ButtonStyle get secondaryButton => OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Colors.white30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}
