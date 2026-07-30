import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SplashScreen extends StatefulWidget {
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    try {
      await Future.delayed(const Duration(seconds: 2));

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      debugPrint('TOKEN: $token');

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {

        final response = await http.post(
          Uri.parse("https://prons.kz/ajax/check.php"),
          body: {"token": token},
        ).timeout(const Duration(seconds: 5));

        final data = json.decode(response.body);

        if (data["result"] != null && data["result"]["valid"] == true) {
          // Сохраняем user_id на случай, если он ещё не был сохранён
          // (например, у пользователей, залогиненных до этого обновления).
          final userId = data["result"]["user_id"]?.toString();
          if (userId != null) {
            await prefs.setString('user_id', userId);
          }

          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          return;
        }

        // токен невалидный → удаляем
        await prefs.remove('auth_token');
        await prefs.remove('user_id');
      }

      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);

    } catch (e, st) {
      debugPrint('Splash error: $e\n$st');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
