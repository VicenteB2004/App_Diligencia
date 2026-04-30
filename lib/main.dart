import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notificador/app/app.dart';
import 'package:notificador/features/auth/presentation/pages/session_page.dart';

// 🔥 IMPORTANTE
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[APP][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) {
    debugPrint('[APP][PlatformError] $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('[APP][ErrorWidget] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }

    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                'Ocurrio un error al cargar la pantalla.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    const NotificadorApp(
      home: SessionPage(),
    ),
  );
}