import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/data/services/auth_service.dart';
import 'package:notificador/features/auth/presentation/pages/login_page.dart';
import 'package:notificador/features/operacion/presentation/pages/operacion_mapa_page.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final AuthService _authService = AuthService();
  Usuario? _usuario;

  void _onLoginSuccess(Usuario usuario) {
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _usuario = usuario;
      });
    });
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _usuario = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Usuario? usuario = _usuario;
    if (usuario == null) {
      return LoginPage(onLoginSuccess: _onLoginSuccess);
    }

    return OperacionMapaPage(
      title: 'Mapa Notificador',
      usuario: usuario,
      onUserUpdated: _onLoginSuccess,
      onLogout: () {
        unawaited(_logout());
      },
    );
  }
}
