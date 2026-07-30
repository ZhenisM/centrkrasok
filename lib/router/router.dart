import 'package:flutter/material.dart';
import 'package:centrkrasok/catalog/product_list/view/product_list_screen.dart';
import 'package:centrkrasok/catalog/product_item/view/product_item_screen.dart';
import 'package:centrkrasok/scanner/scanner_screen.dart';
import 'package:centrkrasok/profile/profile_screen.dart';
import 'package:centrkrasok/pages/main_screen.dart';
import 'package:centrkrasok/auth/login_screen.dart';
import 'package:centrkrasok/auth/splash_screen.dart';
import 'package:centrkrasok/catalog/search/search_screen.dart';
import 'package:centrkrasok/catalog/favorites/favorites_screen.dart';
import 'package:centrkrasok/catalog/compare/compare_screen.dart';

// '/cart' и '/checkout' пока намеренно отсутствуют — мультикорзина и
// оформление заказа будут переделаны отдельно (см. обсуждение).
final routes = {
  '/': (context) => SplashScreen(),
  '/home': (context) => MainScreen(),
  '/auth': (context) => LoginScreen(),
  '/products-list': (context) => const ProductListScreen(),
  '/products-item': (context) => ProductItemScreen(),
  '/scanner': (context) => const ScannerScreen(),
  '/profile': (context) => const ProfileScreen(),
  '/search': (context) => const SearchScreen(),
  '/favorites': (context) => const FavoritesScreen(),
  '/compare': (context) => const CompareScreen(),
};
