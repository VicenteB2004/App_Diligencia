import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/grupo_notificador.dart';
import 'package:notificador/data/models/notification_report.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/data/repositories/auth_repository.dart';
import 'package:notificador/data/services/auth_service.dart';
import 'package:notificador/data/services/firestore_service.dart';
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
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _codigoInvitacionCtrl = TextEditingController();

  AppUser? _appUser;
  bool _loading = false;
  String? _expulsandoUid;
  String? _codigoGenerado;
  Future<List<GrupoNotificador>>? _notificadoresFuture;

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
      _refrescarNotificadores();
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

  void _refrescarNotificadores() {
    if (!mounted) {
      return;
    }
    setState(() {
      _notificadoresFuture = _cargarNotificadoresDelGrupo();
    });
  }

  Future<List<GrupoNotificador>> _cargarNotificadoresDelGrupo() async {
    final AppUser? appUser = _appUser;
    final bool esAbogado =
        appUser != null ? appUser.rol == UserRole.abogado : widget.usuario.rol == RolApp.abogado;
    final String groupId = (appUser?.groupId ?? widget.usuario.groupId).trim();
    if (!esAbogado || groupId.isEmpty) {
      return <GrupoNotificador>[];
    }

    try {
      final List<GrupoNotificador> desdeInvitaciones = await _authService.getNotificadoresByCurrentUserGroup();

      // Si desde invitaciones obtuvimos mas de uno, devolvemos directamente.
      // Si no, intentamos complementar con reportes (fallback) para cubrir casos
      // donde las invitaciones no estan disponibles o faltan permisos de lectura.
      if (desdeInvitaciones.length > 1) {
        return desdeInvitaciones;
      }

      // Intentamos fallback pero sin lanzar si falla; devolvemos lo obtenido.
      try {
        final List<NotificationReport> reportes = await _firestoreService.getNotificationReportsByCurrentUserGroup(limit: 500);
        final Map<String, GrupoNotificador> porUid = <String, GrupoNotificador>{};
        for (final NotificationReport reporte in reportes) {
          final String uid = reporte.notificadorUid.trim();
          final String email = reporte.notificadorEmail.trim();
          if (uid.isEmpty || email.isEmpty || porUid.containsKey(uid)) {
            continue;
          }

          porUid[uid] = GrupoNotificador(
            uid: uid,
            email: email,
            nombre: reporte.notificadorNombre.trim().isEmpty ? email.split('@').first : reporte.notificadorNombre.trim(),
            groupId: reporte.groupId.trim().isEmpty ? groupId : reporte.groupId.trim(),
            joinCode: null,
          );
        }

        // Merge invitaciones + fallback, preservando unicidad por uid.
        final Map<String, GrupoNotificador> merged = <String, GrupoNotificador>{};
        for (final GrupoNotificador g in desdeInvitaciones) {
          merged[g.uid] = g;
        }
        for (final GrupoNotificador g in porUid.values) {
          merged.putIfAbsent(g.uid, () => g);
        }

        final List<GrupoNotificador> resultado = merged.values.toList();
        resultado.sort((GrupoNotificador a, GrupoNotificador b) {
          final int cmp = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
          if (cmp != 0) return cmp;
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
        });
        return resultado;
      } catch (_) {
        // Si fallback falla, devolvemos lo que obtuvimos desde invitaciones (aunque sea 0 o 1).
        return desdeInvitaciones;
      }
    } on AuthServiceException catch (e) {
      final String codigo = (e.code ?? '').trim().toLowerCase();
      final String mensaje = e.message.toLowerCase();
      if (codigo != 'permission-denied' && !mensaje.contains('permission-denied')) {
        rethrow;
      }

      final List<NotificationReport> reportes = await _firestoreService.getNotificationReportsByCurrentUserGroup(limit: 500);
      final Map<String, GrupoNotificador> porUid = <String, GrupoNotificador>{};
      for (final NotificationReport reporte in reportes) {
        final String uid = reporte.notificadorUid.trim();
        final String email = reporte.notificadorEmail.trim();
        if (uid.isEmpty || email.isEmpty || porUid.containsKey(uid)) {
          continue;
        }

        porUid[uid] = GrupoNotificador(
          uid: uid,
          email: email,
          nombre: reporte.notificadorNombre.trim().isEmpty ? email.split('@').first : reporte.notificadorNombre.trim(),
          groupId: reporte.groupId.trim().isEmpty ? groupId : reporte.groupId.trim(),
          joinCode: null,
        );
      }

      final List<GrupoNotificador> fallback = porUid.values.toList();
      fallback.sort((GrupoNotificador a, GrupoNotificador b) {
        final int cmp = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
        if (cmp != 0) {
          return cmp;
        }
        return a.email.toLowerCase().compareTo(b.email.toLowerCase());
      });
      return fallback;
    }
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
      _refrescarNotificadores();
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

  Future<void> _expulsarNotificador(GrupoNotificador notificador) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Expulsar notificador'),
          content: Text(
            'Vas a expulsar a ${notificador.nombre}. Esta persona perdera el acceso al grupo.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Expulsar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    setState(() {
      _expulsandoUid = notificador.uid;
    });

    try {
      await _authService.expulsarNotificadorDelGrupo(notificador.uid);
      _mostrarMensaje('${notificador.nombre} fue expulsado del grupo.');
      _refrescarNotificadores();
    } on AuthServiceException catch (e) {
      _mostrarMensaje(e.message);
    } catch (e) {
      _mostrarMensaje('No se pudo expulsar al notificador: $e');
    } finally {
      if (mounted) {
        setState(() {
          _expulsandoUid = null;
        });
      }
    }
  }

  Future<void> _diagnosticoNotificadores(String groupId) async {
    final AppUser? perfil = _appUser;
    final String abogadoUid = perfil?.uid ?? '';
    final StringBuffer sb = StringBuffer();

    try {
      sb.writeln('Diagnostico notificadores para groupId: $groupId');

      // 1) Invitaciones creadas por este abogado
      final QuerySnapshot<Map<String, dynamic>> invitacionesSnap = await FirebaseFirestore.instance
          .collection(AuthService.invitacionesCollection)
          .where('groupId', isEqualTo: groupId)
          .where('creadoPorUid', isEqualTo: abogadoUid)
          .get();
      sb.writeln('\nInvitaciones encontradas: ${invitacionesSnap.docs.length}');
      for (final doc in invitacionesSnap.docs) {
        final data = doc.data();
        sb.writeln('- doc: ${doc.id} estado:${(data['estado'] ?? '').toString()} usedByUid:${(data['usedByUid'] ?? '').toString()}');
      }

      // 2) Reportes fallback
      final List<NotificationReport> reportes = await _firestoreService.getNotificationReportsByCurrentUserGroup(limit: 500);
      sb.writeln('\nReportes encontrados: ${reportes.length}');
      final Set<String> uidsFromReports = <String>{};
      for (final r in reportes) {
        uidsFromReports.add(r.notificadorUid.trim());
      }
      sb.writeln('UIDs desde reportes (unique): ${uidsFromReports.length}');

      // 3) Resolver perfiles de usedByUid desde invitaciones
      final Set<String> usedUids = <String>{};
      for (final doc in invitacionesSnap.docs) {
        final String used = (doc.data()['usedByUid'] as String? ?? '').trim();
        if (used.isNotEmpty) usedUids.add(used);
      }
      sb.writeln('\nUIDs usados en invitaciones: ${usedUids.length}');
      for (final uid in usedUids) {
        try {
          final AppUser? u = await _authService.getAppUserByUid(uid);
          sb.writeln('- $uid -> ${u?.email ?? '(no existe)'} rol:${u?.rol.value ?? ''} groupId:${u?.groupId ?? ''}');
        } catch (e) {
          sb.writeln('- $uid -> error leyendo perfil: $e');
        }
      }

      // 4) Mostrar usuarios directos en reportes
      for (final uid in uidsFromReports) {
        try {
          final AppUser? u = await _authService.getAppUserByUid(uid);
          sb.writeln('- reporte uid $uid -> ${u?.email ?? '(no existe)'} rol:${u?.rol.value ?? ''} groupId:${u?.groupId ?? ''}');
        } catch (e) {
          sb.writeln('- reporte uid $uid -> error leyendo perfil: $e');
        }
      }
    } catch (e) {
      sb.writeln('\nError durante diagnostico: $e');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Diagnóstico notificadores'),
        content: SingleChildScrollView(child: SelectableText(sb.toString())),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _buildNotificadoresDelGrupoSection(BuildContext context, {required bool esAbogado, required String groupId}) {
    if (!esAbogado || groupId.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final Future<List<GrupoNotificador>> future = _notificadoresFuture ?? _cargarNotificadoresDelGrupo();

    return FutureBuilder<List<GrupoNotificador>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<GrupoNotificador>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('No se pudieron cargar los notificadores del grupo.'),
            ),
          );
        }

        final List<GrupoNotificador> notificadores = snapshot.data ?? <GrupoNotificador>[];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.groups_2_outlined),
                    SizedBox(width: 8),
                    Text('Notificadores del grupo', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  notificadores.isEmpty
                      ? 'Aun no hay notificadores asignados a este grupo.'
                      : 'Estos son los notificadores que se unieron con invitaciones de tu grupo.',
                ),
                const SizedBox(height: 8),
                // Boton de diagnostico para entornos de desarrollo / debugging.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _diagnosticoNotificadores(groupId),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Diagnóstico'),
                  ),
                ),
                 if (notificadores.isNotEmpty) ...<Widget>[
                   const SizedBox(height: 12),
                   SizedBox(
                     height: 300,
                     child: ListView.separated(
                       itemCount: notificadores.length,
                       shrinkWrap: false,
                       physics: const AlwaysScrollableScrollPhysics(),
                       separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final GrupoNotificador notificador = notificadores[index];
                      final bool expulsando = _expulsandoUid == notificador.uid;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (notificador.nombre.isNotEmpty ? notificador.nombre : notificador.email)
                                  .substring(0, 1)
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(notificador.nombre),
                          subtitle: Text(
                            '${notificador.email}\n'
                            'Codigo usado: ${notificador.joinCode?.isNotEmpty == true ? notificador.joinCode : 'No registrado'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Expulsar del grupo',
                            onPressed: expulsando ? null : () => _expulsarNotificador(notificador),
                            icon: expulsando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.person_remove_alt_1_outlined),
                          ),
                        ),
                       );
                     },
                   ),
                 ),
                 ],
              ],
            ),
          ),
        );
      },
    );
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
                if (esAbogado) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildNotificadoresDelGrupoSection(
                    context,
                    esAbogado: esAbogado,
                    groupId: groupId,
                  ),
                ],
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



