import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio_lib;
import 'package:shared_preferences/shared_preferences.dart';



class LoginScreen  extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen > {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> loginUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dioClient = dio_lib.Dio(dio_lib.BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final dioResp = await dioClient.post(
        'https://prons.kz/ajax/login.php',
        data: 'login=${Uri.encodeComponent(_loginController.text)}&password=${Uri.encodeComponent(_passwordController.text)}',
        options: dio_lib.Options(
          contentType: 'application/x-www-form-urlencoded',
          responseType: dio_lib.ResponseType.plain,
        ),
      );

      if (dioResp.statusCode == 200) {
        final body = dioResp.data?.toString() ?? '';
        if (body.isNotEmpty) {
          final data = json.decode(body);

          if (data["result"] != null) {
            String token = data["result"]["token"];
            String? userId = data["result"]["user_id"]?.toString();
            String? fullName = data["result"]["full_name"]?.toString();

            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString("auth_token", token);
            if (userId != null) {
              await prefs.setString("user_id", userId);
            }
            if (fullName != null && fullName.isNotEmpty) {
              await prefs.setString("user_name", fullName);
            }

            // Сохраняем куки сессии для WebView
            // login.php на prons.kz устанавливает PHPSESSID и BITRIX_SM_*
            // Собираем ВСЕ Set-Cookie через dio
            final cookieParts = dioResp.headers.map['set-cookie'] ?? [];
            if (cookieParts.isNotEmpty) {
              await prefs.setString('session_cookies', cookieParts.join(', '));
            }

            if (mounted) Navigator.pushReplacementNamed(context, "/home");
          } else {
            setState(() {
              _errorMessage = data["error_description"] ?? "Ошибка авторизации";
            });
          }
        } else {
          setState(() => _errorMessage = "Пустой ответ сервера");
        }
      } else {
        setState(() => _errorMessage = "Ошибка сервера: ${dioResp.statusCode}");
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Авторизация")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _loginController,
              decoration: InputDecoration(labelText: "Логин"),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: "Пароль"),
              obscureText: true,
            ),
            SizedBox(height: 20),
            if (_errorMessage != null)
              Text(_errorMessage!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
              onPressed: loginUser,
              child: Text("Войти"),
            ),
          ],
        ),
      ),
    );
  }
}
