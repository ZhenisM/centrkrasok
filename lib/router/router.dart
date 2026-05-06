import 'package:flutter/material.dart';
import 'package:centrkrasok/catalog/product_list/view/product_list_screen.dart';
import 'package:centrkrasok/catalog/product_item/view/product_item_screen.dart';
import 'package:centrkrasok/pages/home.dart';
import 'package:centrkrasok/pages/main_screen.dart';
import 'package:centrkrasok/auth/login_screen.dart';
import 'package:centrkrasok/auth/splash_screen.dart';

final routes = {
  '/': (context) => SplashScreen(),
  '/home': (context) => MainScreen(),
  '/auth': (context) => LoginScreen(),
  '/products-list': (context) => const ProductListScreen(),
  '/products-item': (context) => const ProductItemScreen(),
};