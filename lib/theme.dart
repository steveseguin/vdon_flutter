import 'package:flutter/material.dart';

// Define colors
Color ninjaDarkBlue = Color(0xFF2C3E50);  // Soft dark blue
Color ninjaDarkerBlue = Color(0xFF34495E); // Slightly darker shade
Color ninjaBackgroundColor = Color(0xFF2C3E50);
Color ninjaCardColor = Colors.white.withOpacity(0.9);  // Slightly softened white
Color ninjaDialogColor = ninjaDarkerBlue;  // Use darker blue for dialogs
Color ninjaAccentColor = Color(0xFF3498DB);  // Light blue for accents

var theme = ThemeData(
  primaryColor: ninjaDarkBlue,
  scaffoldBackgroundColor: ninjaDarkBlue,
  cardTheme: CardTheme(
    color: ninjaCardColor,
    elevation: 2,
  ),
  canvasColor: ninjaDarkerBlue,
  textTheme: TextTheme(
    displayLarge: TextStyle(fontSize: 25.0, fontWeight: FontWeight.normal, color: Colors.white),
    displayMedium: TextStyle(fontSize: 15.0, color: Colors.red),
    displaySmall: TextStyle(fontSize: 15.0, color: Colors.white),
  ),
  colorScheme: ColorScheme.fromSwatch().copyWith(
    secondary: ninjaDarkerBlue,
    background: ninjaBackgroundColor,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: ninjaDarkBlue,
    elevation: 0,
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.white70,
      textStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
  iconTheme: IconThemeData(
    color: Colors.white70,
    size: 24,
  ),
  // Add dialog theme
  dialogTheme: DialogTheme(
    backgroundColor: ninjaDialogColor,
    elevation: 8,
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    contentTextStyle: TextStyle(
      color: Colors.white,
    ),
  ),
  // Add input decoration theme
  inputDecorationTheme: InputDecorationTheme(
    labelStyle: TextStyle(color: Colors.white70),
    hintStyle: TextStyle(color: Colors.white54),
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: Colors.white54),
    ),
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: Colors.white),
    ),
  ),
  // Update the dialog action button colors
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: Colors.white,
    selectionColor: Colors.white24,
    selectionHandleColor: Colors.white70,
  ),
);
