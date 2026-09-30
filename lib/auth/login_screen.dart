import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  bool _obscurePassword = true;

  bool get _canSubmit =>
      _loginController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Кнопка "Войти" должна включаться/выключаться по мере ввода —
    // пересобираем экран при любом изменении текста в полях.
    _loginController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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

  InputDecoration _fieldDecoration({required String hint, Widget? suffixIcon}) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(Colors.black, 1.5),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        title: const Text("Авторизация"),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _loginController,
                decoration: _fieldDecoration(hint: "Логин"),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: _fieldDecoration(
                  hint: "Пароль",
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: SvgPicture.asset(
                      _obscurePassword ? 'assets/icons/eye-crossed.svg' : 'assets/icons/eye.svg',
                      width: 20, height: 20,
                      colorFilter: ColorFilter.mode(Colors.grey.shade500, BlendMode.srcIn),
                    ),
                  ),
                ),
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                // "Готово" на клавиатуре = "Войти", если оба поля заполнены.
                onSubmitted: (_) {
                  if (_canSubmit && !_isLoading) loginUser();
                },
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _canSubmit ? loginUser : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade500,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          "Войти",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
