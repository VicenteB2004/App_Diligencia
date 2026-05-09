import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:notificador/data/local/database_helper.dart';
import 'package:notificador/data/models/ubicacion.dart';
import 'package:notificador/data/models/visita.dart';
import 'package:sqflite/sqflite.dart';

class UbicacionesRepository {
  UbicacionesRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<int> crearUbicacionAbogado({
    required int abogadoId,
    required LatLng posicion,
    String? direccion,
    String? descripcion,
    String? nombreUbicacion,
    String? referenciaUbicacion,
    String? identificacionTecnica,
    String? razonSocial,
    String? ruc,
    String? representanteLegal,
    String? nombreNotificador,
    String? cedulaNotificador,
    bool esSegundaNotificacion = false,
  }) async {
    final Database db = await _dbHelper.database;
    final Ubicacion nueva = Ubicacion(
      abogadoId: abogadoId,
      latitud: posicion.latitude,
      longitud: posicion.longitude,
      direccion: direccion,
      descripcion: descripcion,
      nombreUbicacion: nombreUbicacion,
      referenciaUbicacion: referenciaUbicacion,
      identificacionTecnica: identificacionTecnica,
      razonSocial: razonSocial,
      ruc: ruc,
      representanteLegal: representanteLegal,
      nombreNotificador: nombreNotificador,
      cedulaNotificador: cedulaNotificador,
      esSegundaNotificacion: esSegundaNotificacion,
      fechaCreacion: DateTime.now(),
      estado: 'pendiente',
    );

    return db.insert(
      DatabaseHelper.tablaUbicaciones,
      nueva.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<int>> crearUbicacionesAbogadoBatch({
    required int abogadoId,
    required List<NuevaUbicacionInput> entradas,
  }) async {
    if (entradas.isEmpty) {
      return <int>[];
    }

    final Database db = await _dbHelper.database;
    return db.transaction<List<int>>((Transaction txn) async {
      final List<int> ids = <int>[];
      for (final NuevaUbicacionInput entrada in entradas) {
        final Ubicacion nueva = Ubicacion(
          abogadoId: abogadoId,
          latitud: entrada.posicion.latitude,
          longitud: entrada.posicion.longitude,
          direccion: entrada.direccion,
          descripcion: entrada.descripcion,
          nombreUbicacion: entrada.nombreUbicacion,
          referenciaUbicacion: entrada.referenciaUbicacion,
          identificacionTecnica: entrada.identificacionTecnica,
          razonSocial: entrada.razonSocial,
          ruc: entrada.ruc,
          representanteLegal: entrada.representanteLegal,
          nombreNotificador: entrada.nombreNotificador,
          cedulaNotificador: entrada.cedulaNotificador,
          esSegundaNotificacion: entrada.esSegundaNotificacion,
          fechaCreacion: DateTime.now(),
          estado: 'pendiente',
        );

        final int id = await txn.insert(
          DatabaseHelper.tablaUbicaciones,
          nueva.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        ids.add(id);
      }
      return ids;
    });
  }

  Future<List<Ubicacion>> listarUbicaciones({String? estado, int? abogadoId}) async {
    final Database db = await _dbHelper.database;

    final List<String> whereParts = <String>[];
    final List<Object> whereArgs = <Object>[];
    if (estado != null) {
      whereParts.add('estado = ?');
      whereArgs.add(estado);
    }
    if (abogadoId != null) {
      whereParts.add('abogado_id = ?');
      whereArgs.add(abogadoId);
    }

    final List<Map<String, Object?>> rows = await db.query(
      DatabaseHelper.tablaUbicaciones,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereParts.isEmpty ? null : whereArgs,
      orderBy: 'fecha_creacion ASC',
    );

    return rows.map(Ubicacion.fromMap).toList();
  }

  Future<void> marcarUbicacionCompletada(int ubicacionId) async {
    final Database db = await _dbHelper.database;
    await db.update(
      DatabaseHelper.tablaUbicaciones,
      <String, Object?>{'estado': 'completada'},
      where: 'id = ?',
      whereArgs: <Object>[ubicacionId],
    );
  }

  Future<int> registrarVisitaNotificador({
    required int ubicacionId,
    required int notificadorId,
    required LatLng ubicacionLlegada,
    String? observacion,
  }) async {
    final Database db = await _dbHelper.database;

    return db.transaction<int>((Transaction txn) async {
      final DateTime now = DateTime.now();
      final Visita visita = Visita(
        ubicacionId: ubicacionId,
        notificadorId: notificadorId,
        latitud: ubicacionLlegada.latitude,
        longitud: ubicacionLlegada.longitude,
        fecha: _formatDate(now),
        hora: _formatTime(now),
        estado: 'completada',
        observacion: observacion,
      );

      final int visitaId = await txn.insert(
        DatabaseHelper.tablaVisitas,
        visita.toMap()..remove('id'),
      );

      await txn.update(
        DatabaseHelper.tablaUbicaciones,
        <String, Object?>{'estado': 'completada'},
        where: 'id = ?',
        whereArgs: <Object>[ubicacionId],
      );

      return visitaId;
    });
  }

  Future<List<Visita>> listarVisitas() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseHelper.tablaVisitas,
      orderBy: 'fecha ASC, hora ASC',
    );

    return rows.map(Visita.fromMap).toList();
  }

  Future<void> borrarTodasLasUbicaciones() async {
    final Database db = await _dbHelper.database;
    await db.delete(DatabaseHelper.tablaUbicaciones);
  }

  Future<void> borrarUbicacionesPorAbogado(int abogadoId) async {
    final Database db = await _dbHelper.database;
    await db.transaction<void>((Transaction txn) async {
      final List<Map<String, Object?>> ubicaciones = await txn.query(
        DatabaseHelper.tablaUbicaciones,
        columns: <String>['id'],
        where: 'abogado_id = ?',
        whereArgs: <Object>[abogadoId],
      );

      final List<int> ubicacionIds = ubicaciones
          .map((Map<String, Object?> row) => row['id'] as int?)
          .whereType<int>()
          .toList();

      if (ubicacionIds.isNotEmpty) {
        final String inClause = List<String>.filled(ubicacionIds.length, '?').join(',');
        await txn.delete(
          DatabaseHelper.tablaVisitas,
          where: 'ubicacion_id IN ($inClause)',
          whereArgs: ubicacionIds,
        );
      }

      await txn.delete(
        DatabaseHelper.tablaUbicaciones,
        where: 'abogado_id = ?',
        whereArgs: <Object>[abogadoId],
      );
    });
  }

  String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class NuevaUbicacionInput {
  const NuevaUbicacionInput({
    required this.posicion,
    this.direccion,
    this.descripcion,
    this.nombreUbicacion,
    this.referenciaUbicacion,
    this.identificacionTecnica,
    this.razonSocial,
    this.ruc,
    this.representanteLegal,
    this.nombreNotificador,
    this.cedulaNotificador,
    this.esSegundaNotificacion = false,
  });

  final LatLng posicion;
  final String? direccion;
  final String? descripcion;
  final String? nombreUbicacion;
  final String? referenciaUbicacion;
  final String? identificacionTecnica;
  final String? razonSocial;
  final String? ruc;
  final String? representanteLegal;
  final String? nombreNotificador;
  final String? cedulaNotificador;
  final bool esSegundaNotificacion;
}

