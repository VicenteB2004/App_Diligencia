import 'package:flutter/material.dart';

class NotificadorApp extends StatelessWidget {
  const NotificadorApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Notificador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: home,
    );
  }
}

