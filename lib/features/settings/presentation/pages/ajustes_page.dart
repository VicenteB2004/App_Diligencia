import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/data/repositories/auth_repository.dart';
import 'package:notificador/data/services/auth_service.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';

class AjustesPage extends StatefulWidget {
  const AjustesPage({
    super.key,
    required this.usuario,
    required this.onUsuarioActualizado,
  });

  final Usuario usuario;
  final ValueChanged<Usuario> onUsuarioActualizado;

  @override
  State<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends State<AjustesPage> {
  final AuthService _authService = AuthService();
  final AuthRepository _authRepository = AuthRepository();
  final TextEditingController _codigoInvitacionCtrl = TextEditingController();

  AppUser? _appUser;
  bool _loading = false;
  String? _codigoGenerado;

  @override
  void initState() {
    super.initState();
    unawaited(_cargarPerfil());
  }

  @override
  void dispose() {
    _codigoInvitacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    setState(() {
      _loading = true;
    });

    try {
      final AppUser? perfil = await _authService.getCurrentAppUser();
      if (!mounted) {
        return;
      }
      setState(() {
        _appUser = perfil;
      });
      if (perfil != null) {
        await _sincronizarUsuarioLocal(perfil);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje('No se pudo cargar tu perfil: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _sincronizarUsuarioLocal(AppUser appUser) async {
    final Usuario local = await _authRepository.upsertLocalFromAppUser(appUser);
    if (!mounted) {
      return;
    }
    widget.onUsuarioActualizado(local);
  }

  Future<void> _generarInvitacion() async {
    setState(() {
      _loading = true;
    });

    try {
      final String codigo = await _authService.generarInvitacionGrupo();
      final AppUser? actualizado = await _authService.getCurrentAppUser();
      if (!mounted) {
        return;
      }
      setState(() {
        _codigoGenerado = codigo;
        _appUser = actualizado ?? _appUser;
      });
      if (actualizado != null) {
        await _sincronizarUsuarioLocal(actualizado);
      }
      _mostrarMensaje('Codigo generado. Compartelo con un notificador.');
    } on AuthServiceException catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje(e.message);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje('No se pudo generar la invitacion: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _unirseAGrupo() async {
    setState(() {
      _loading = true;
    });

    try {
      final AppUser actualizado = await _authService.unirseAGrupoConInvitacion(
        _codigoInvitacionCtrl.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _appUser = actualizado;
      });
      await _sincronizarUsuarioLocal(actualizado);
      _codigoInvitacionCtrl.clear();
      _mostrarMensaje('Te uniste correctamente al grupo ${actualizado.groupId}.');
    } on AuthServiceException catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje(e.message);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _mostrarMensaje('No se pudo unir al grupo: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _copiarCodigo() {
    final String? codigo = _codigoGenerado;
    if (codigo == null || codigo.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: codigo));
    _mostrarMensaje('Codigo copiado al portapapeles.');
  }

  void _mostrarMensaje(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? appUser = _appUser;
    final bool esAbogado =
        appUser != null ? appUser.rol == UserRole.abogado : widget.usuario.rol == RolApp.abogado;
    final bool esNotificador = !esAbogado;
    final String groupId = (appUser?.groupId ?? widget.usuario.groupId).trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes de usuario')),
      body: _loading && appUser == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            Icon(Icons.badge_outlined),
                            SizedBox(width: 8),
                            Text('Mi grupo', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          groupId.isEmpty ? 'No tienes grupo asignado.' : 'Grupo actual: $groupId',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Rol: ${esAbogado ? 'Abogado' : 'Notificador'}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (esAbogado)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              Icon(Icons.group_add_outlined),
                              SizedBox(width: 8),
                              Text('Invitar al grupo', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Solo abogado puede generar invitaciones para que notificador se una al grupo.',
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'El codigo vence en 24 horas y se desactiva al primer uso.',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _loading ? null : _generarInvitacion,
                            icon: const Icon(Icons.key),
                            label: const Text('Generar codigo de invitacion'),
                          ),
                          if ((_codigoGenerado ?? '').isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      'Codigo: $_codigoGenerado',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Copiar',
                                    onPressed: _copiarCodigo,
                                    icon: const Icon(Icons.copy),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (esNotificador)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              Icon(Icons.how_to_reg_outlined),
                              SizedBox(width: 8),
                              Text('Unirme a un grupo', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _codigoInvitacionCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Codigo de invitacion',
                              hintText: 'Ej: A1B2C3',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _loading ? null : _unirseAGrupo,
                            icon: const Icon(Icons.login),
                            label: const Text('Unirme al grupo'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}



