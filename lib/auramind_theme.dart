import 'package:flutter/material.dart';
import 'package:auramind/models/auramind_models.dart';

// AuraMind design tokens.
//
// Palette: cream (#F5F3EF), darkGray (#3F4A3E), lightGreen (#8FA88D),
// warmGray (#6D716A), surface (#FAFAF8), accentBlue (#5B8DEF).
//
// Screens reference `C.xxx` everywhere, so colours change in one place.

class C {
  // ── Backgrounds ───────────────────────────────────────────
  static const bg      = Color(0xFFF5F3EF);   // cream
  static const surface = Color(0xFFFAFAF8);   // surface
  static const card    = Color(0xFFFFFFFF);

  // ── Primary — lightGreen ─────────────────────────
  static const accent     = Color(0xFF8FA88D);  // lightGreen
  static const accentMed  = Color(0xFFA7BDA5);  // lighter green
  static const accentSoft = Color(0xFFECF2EB);  // pale green wash
  static const accentPill = Color(0xFFE0EAE0);  // soft pill bg
  static const accentDark = Color(0xFF3F4A3E);  // darkGray (emphasis)

  // ── Secondary — accentBlue ───────────────────────
  static const teal     = Color(0xFF5B8DEF);   // accentBlue
  static const tealSoft = Color(0xFFE8F0FD);   // pale blue wash

  // ── Text — grays ─────────────────────────────────
  static const t1 = Color(0xFF3F4A3E);   // darkGray
  static const t2 = Color(0xFF6D716A);   // warmGray
  static const t3 = Color(0xFF9A9D98);   // lighter warm gray
  static const t4 = Color(0xFFC2C4BF);   // lightest

  // ── Borders ───────────────────────────────────────────────
  static const border  = Color(0xFFE2E3DF);
  static const borderL = Color(0xFFF0F0ED);

  // ── Semantic ──────────────────────────────────────────────
  static const danger      = Color(0xFFC0413B);
  static const dangerSoft  = Color(0xFFFBEEED);
  static const warning     = Color(0xFFC07A2C);
  static const warningSoft = Color(0xFFFBF3E9);
  static const success     = Color(0xFF5A8F5E);  // green-tinted success
  static const successSoft = Color(0xFFE7F2E8);

  // ── Soft elevation ────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(color: const Color(0xFF3F4A3E).withValues(alpha: 0.05),
            blurRadius: 14, offset: const Offset(0, 4)),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(color: const Color(0xFF3F4A3E).withValues(alpha: 0.08),
            blurRadius: 24, offset: const Offset(0, 8)),
      ];

  // ── Mood spectrum — soft tones ───────
  static Color mood(MoodLevel l) {
    switch (l) {
      case MoodLevel.excellent: return const Color(0xFF5A8F5E); // forest green
      case MoodLevel.good:      return const Color(0xFF8FA88D); // lightGreen
      case MoodLevel.neutral:   return const Color(0xFFC09A4B); // muted gold
      case MoodLevel.low:       return const Color(0xFFCB7B4A); // soft clay
      case MoodLevel.veryLow:   return const Color(0xFFC0413B); // muted red
    }
  }

  static Color moodSoft(MoodLevel l) {
    switch (l) {
      case MoodLevel.excellent: return const Color(0xFFE7F2E8);
      case MoodLevel.good:      return const Color(0xFFECF2EB);
      case MoodLevel.neutral:   return const Color(0xFFFAF3E4);
      case MoodLevel.low:       return const Color(0xFFFBEFE6);
      case MoodLevel.veryLow:   return const Color(0xFFFBEEED);
    }
  }
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.accent,
      surface: C.surface,
      primary: C.accent,
    ),
    splashColor: C.accent.withValues(alpha: 0.06),
    highlightColor: C.accent.withValues(alpha: 0.04),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.border, width: 0.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.border, width: 0.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.accent, width: 1.5)),
    ),
  );
}
