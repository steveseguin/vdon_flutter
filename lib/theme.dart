import 'package:flutter/material.dart';

Color ninjaDarkBlue = Color(0xff141926);
Color ninjaPrimaryColor = Color(0xffFE003B);
Color ninjaBackgroundColor = Color(0xff141926);
Color ninjaCardColor = Color(0xffdddddd);

var theme = ThemeData(
  primaryColor: ninjaPrimaryColor,
  backgroundColor: ninjaBackgroundColor,
  cardTheme: CardTheme(color: ninjaCardColor, elevation: 1),
  accentColor: ninjaPrimaryColor,
  canvasColor: ninjaDarkBlue,
  textTheme: TextTheme(
    headline1: TextStyle(fontSize: 25.0, fontWeight: FontWeight.normal),
    headline2: TextStyle(fontSize: 15.0, color: Colors.red),
    headline3: TextStyle(fontSize: 15.0, color: Colors.white),
  ),
);
