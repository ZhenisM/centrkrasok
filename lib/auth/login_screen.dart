import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

    final response = await http.post(
      Uri.parse("https://prons.kz/ajax/login.php"),
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: {
        "login": _loginController.text,
        "password": _passwordController.text,
      },
    );

    setState(() {
      _isLoading = false;
    });

    if (response.statusCode == 200) {
      if (response.body.isNotEmpty) {

        final data = json.decode(response.body);

        if (data["result"] != null) {
          String token = data["result"]["token"];

          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString("auth_token", token);

          Navigator.pushReplacementNamed(context, "/home");
        } else {
          setState(() {
            _errorMessage = data["error_description"] ?? "Ошибка авторизации";
          });
        }

      } else {
        setState(() {
          _errorMessage = "Пустой ответ сервера";
        });
      }
    } else {
      setState(() {
        _errorMessage = "Ошибка сервера: ${response.statusCode}";
      });
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
