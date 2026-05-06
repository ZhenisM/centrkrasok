import 'package:flutter/material.dart';

const primaryColor = Color(0xFF005095);

final darkTheme = ThemeData(
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.light(
    primary: Colors.black,
    secondary: Colors.green,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: primaryColor,
    iconTheme: IconThemeData(
      color: Colors.white, // иконки слева
    ),
    actionsIconTheme: IconThemeData(
      color: Colors.white, // иконки справа (menu и т.д.)
    ),
    titleTextStyle: TextStyle(
      color: Colors.white, // цвет текста заголовка
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
  dividerColor: Colors.white24,
  listTileTheme: const ListTileThemeData(iconColor: Colors.black),
  textTheme: TextTheme(
    bodyMedium: const TextStyle(
      color: Colors.black, // цвет текста заголовка
      fontSize: 20,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: TextStyle(
      color: Colors.white.withOpacity(0.6),
      fontWeight: FontWeight.w500,
      fontSize: 16,
    ),
  ),
);