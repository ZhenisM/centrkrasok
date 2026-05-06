import 'package:flutter/material.dart';
import 'package:centrkrasok/router/router.dart';
import 'package:centrkrasok/theme/theme.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
    theme: darkTheme,
    initialRoute: '/',
    routes: routes,
  ));
}

