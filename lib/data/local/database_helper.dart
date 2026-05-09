import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String databaseName = 'notificador_local.db';
  static const int databaseVersion = 8;

  static const String tablaUsuarios = 'usuarios';
  static const String tablaUbicaciones = 'ubicaciones';
  static const String tablaVisitas = 'visitas';

  Database? _db;

  Future<Database> get database async {
    final Database? db = _db;
    if (db != null) {
      return db;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath = await getDatabasesPath();
    final String path = p.join(dbPath, databaseName);

    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tablaUsuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        email TEXT UNIQUE,
        password TEXT,
        rol TEXT,
        group_id TEXT,
        fecha_creacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablaUbicaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        abogado_id INTEGER,
        latitud REAL,
        longitud REAL,
        direccion TEXT,
        descripcion TEXT,
        nombre_ubicacion TEXT,
        referencia_ubicacion TEXT,
        identificacion_tecnica TEXT,
        razon_social TEXT,
        ruc TEXT,
        representante_legal TEXT,
        cedula_abogado TEXT,
        nombre_notificador TEXT,
        cedula_notificador TEXT,
        es_segunda_notificacion INTEGER DEFAULT 0,
        estado TEXT DEFAULT 'pendiente',
        fecha_creacion TEXT,
        FOREIGN KEY (abogado_id) REFERENCES $tablaUsuarios(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablaVisitas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ubicacion_id INTEGER,
        notificador_id INTEGER,
        latitud REAL,
        longitud REAL,
        fecha TEXT,
        hora TEXT,
        estado TEXT,
        observacion TEXT,
        FOREIGN KEY (ubicacion_id) REFERENCES $tablaUbicaciones(id),
        FOREIGN KEY (notificador_id) REFERENCES $tablaUsuarios(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_usuarios_email ON $tablaUsuarios(email)',
    );
    await db.execute(
      'CREATE INDEX idx_ubicaciones_estado ON $tablaUbicaciones(estado)',
    );
    await db.execute(
      'CREATE INDEX idx_ubicaciones_abogado ON $tablaUbicaciones(abogado_id)',
    );
    await db.execute(
      'CREATE INDEX idx_visitas_ubicacion ON $tablaVisitas(ubicacion_id)',
    );
    await db.execute(
      'CREATE INDEX idx_visitas_notificador ON $tablaVisitas(notificador_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Reinicia esquema para alinear columnas y llaves foraneas con el nuevo flujo de login.
      await db.execute('DROP TABLE IF EXISTS $tablaVisitas');
      await db.execute('DROP TABLE IF EXISTS $tablaUbicaciones');
      await db.execute('DROP TABLE IF EXISTS $tablaUsuarios');
      await _onCreate(db, newVersion);
      return;
    }

    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN nombre_ubicacion TEXT',
      );
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN identificacion_tecnica TEXT',
      );
    }

    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN referencia_ubicacion TEXT',
      );
    }

    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN razon_social TEXT',
      );
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN ruc TEXT',
      );
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN representante_legal TEXT',
      );
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN cedula_abogado TEXT',
      );
    }

    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN nombre_notificador TEXT',
      );
      await db.execute(
        'ALTER TABLE $tablaUbicaciones ADD COLUMN cedula_notificador TEXT',
      );
    }

    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE $tablaUsuarios ADD COLUMN group_id TEXT',
      );
    }

    if (oldVersion < 8) {
      final bool existeReferencia = await _columnaExiste(
        db,
        tablaUbicaciones,
        'referencia_ubicacion',
      );
      if (!existeReferencia) {
        await db.execute(
          'ALTER TABLE $tablaUbicaciones ADD COLUMN referencia_ubicacion TEXT',
        );
      }

      final bool existeColumna = await _columnaExiste(
        db,
        tablaUbicaciones,
        'es_segunda_notificacion',
      );
      if (!existeColumna) {
        await db.execute(
          'ALTER TABLE $tablaUbicaciones ADD COLUMN es_segunda_notificacion INTEGER DEFAULT 0',
        );
      }
    }
  }

  Future<bool> _columnaExiste(
    Database db,
    String tabla,
    String columna,
  ) async {
    final List<Map<String, Object?>> info = await db.rawQuery(
      'PRAGMA table_info($tabla)',
    );
    return info.any((Map<String, Object?> row) => row['name'] == columna);
  }

  Future<void> close() async {
    final Database? db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}

