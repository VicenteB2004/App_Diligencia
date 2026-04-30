import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/data/repositories/auth_repository.dart';
import 'package:notificador/data/services/auth_service.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});

  final ValueChanged<Usuario> onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final AuthRepository _authRepository = AuthRepository();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _groupIdCtrl = TextEditingController();

  bool _loading = false;
  bool _isRegisterMode = false;
  String _selectedRole = 'abogado';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _groupIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String email = _emailCtrl.text.trim().toLowerCase();
    final String password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _mostrarMensaje('Completa email y password.');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final userCredential = await _authService.loginUser(
        email: email,
        password: password,
      );
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        _mostrarMensaje('No se pudo recuperar la sesion de Firebase Auth.');
        return;
      }

      final AppUser? appUser = await _authService.getAppUserByUid(
        firebaseUser.uid,
        fallbackEmail: firebaseUser.email ?? email,
      );

      if (!mounted) {
        return;
      }

      if (appUser == null) {
        _mostrarMensaje(
          'No se encontro el perfil en Firestore para este usuario.',
        );
        return;
      }

      await _goToSession(appUser);
    } on AuthServiceException catch (e) {
      if (!mounted) {
        return;
      }
      final String detail = e.code == null
          ? e.message
          : '${e.message} (code: ${e.code})';
      _mostrarMensaje(detail);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje('Ocurrio un error inesperado al ingresar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _register() async {
    final String email = _emailCtrl.text.trim().toLowerCase();
    final String password = _passwordCtrl.text;
    final String groupId = _groupIdCtrl.text.trim();
    final bool esAbogado = _selectedRole == 'abogado';

    if (email.isEmpty || password.isEmpty) {
      _mostrarMensaje('Completa email, password y rol.');
      return;
    }
    if (esAbogado && groupId.isEmpty) {
      _mostrarMensaje('Para abogado, el groupId es obligatorio.');
      return;
    }
    if (password.length < 6) {
      _mostrarMensaje('La password debe tener al menos 6 caracteres.');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final AppUser appUser = await _authService.registerUser(
        email: email,
        password: password,
        rol: _selectedRole,
        groupId: groupId,
      );

      if (!mounted) {
        return;
      }

      await _goToSession(appUser);
    } on AuthServiceException catch (e) {
      if (!mounted) {
        return;
      }
      final String detail = e.code == null
          ? e.message
          : '${e.message} (code: ${e.code})';
      _mostrarMensaje(detail);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje('Ocurrio un error inesperado al registrarte: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _goToSession(AppUser appUser) async {
    try {
      Usuario usuarioLocal;
      try {
        usuarioLocal = await _authRepository.upsertLocalFromAppUser(appUser);
      } catch (e) {
        usuarioLocal = Usuario(
          nombre: appUser.email.split('@').first,
          email: appUser.email,
          password: '',
          rol: appUser.rol == UserRole.abogado ? RolApp.abogado : RolApp.notificador,
          fechaCreacion: DateTime.now(),
          groupId: appUser.groupId,
        );
        _mostrarMensaje(
          'Se abrio la sesion, pero no se pudo sincronizar la copia local del usuario: $e',
        );
      }

      if (mounted) {
        widget.onLoginSuccess(usuarioLocal);
      }
    } catch (e) {
      _mostrarMensaje('No se pudo abrir la sesion: $e');
    }
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
    });
  }


  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.account_circle, size: 64),
                  const SizedBox(height: 12),
                  const Text(
                    'Acceso de usuarios',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegisterMode
                        ? 'Crea tu usuario con rol y grupo privado.'
                        : 'Ingresa con tu cuenta registrada en Firebase.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    onSubmitted: (_) {
                      unawaited(_isRegisterMode ? _register() : _login());
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Password',
                    ),
                  ),
                  if (_isRegisterMode) ...<Widget>[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'abogado',
                          child: Text('Abogado'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'notificador',
                          child: Text('Notificador'),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (String? value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedRole = value;
                                if (_selectedRole != 'abogado') {
                                  _groupIdCtrl.clear();
                                }
                              });
                            },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Rol',
                      ),
                    ),
                    if (_selectedRole == 'abogado') ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _groupIdCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Group ID',
                          hintText: 'Ej: grupo-legal-001',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Como abogado debes pertenecer a un grupo para invitar.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : (_isRegisterMode ? _register : _login),
                    icon: Icon(
                      _isRegisterMode ? Icons.person_add : Icons.login,
                    ),
                    label: Text(
                      _loading
                          ? (_isRegisterMode
                                ? 'Registrando...'
                                : 'Ingresando...')
                          : (_isRegisterMode ? 'Registrarme' : 'Ingresar'),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _toggleMode,
                    child: Text(
                      _isRegisterMode
                          ? 'Ya tengo cuenta, quiero ingresar'
                          : 'No tengo cuenta, quiero registrarme',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
