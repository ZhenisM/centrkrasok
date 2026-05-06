import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../theme/theme.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          //backgroundColor: Colors.deepOrangeAccent,
          title: Text('Proff Channel',
            //style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.logout_outlined),
              onPressed: () async {
                bool? confirm = await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Выход"),
                    content: Text("Вы уверены, что хотите выйти?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text("Отмена"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text("Выйти"),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Вы вышли из аккаунта")),
                  );
                  await Future.delayed(Duration(milliseconds: 300));

                  await AuthService.logout();

                  if (!context.mounted) return;

                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/auth',
                        (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Text('Main Screen', style: TextStyle(color: Colors.white),),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/products-list');
              },
              child: Text('Каталог', style: TextStyle(color: Colors.white),),
              style: ElevatedButton.styleFrom(
                elevation: 2,
                shadowColor: Colors.white,
                backgroundColor: Colors.orange,
              ),
            )
          ],
        ),
    );
  }
}


