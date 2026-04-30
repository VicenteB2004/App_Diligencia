import 'package:notificador/data/local/database_helper.dart';
import 'package:notificador/data/models/app_user.dart';
import 'package:notificador/data/models/usuario.dart';
import 'package:notificador/features/operacion/domain/entities/rol_app.dart';
import 'package:sqflite/sqflite.dart';

class AuthRepository {
  AuthRepository({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<void> seedUsuariosDemo() async {
    final Database db = await _dbHelper.database;
    final int? total = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ${DatabaseHelper.tablaUsuarios}'),
    );
    if ((total ?? 0) > 0) {
      return;
    }

    final DateTime now = DateTime.now();
    await db.insert(
      DatabaseHelper.tablaUsuarios,
      Usuario(
        nombre: 'Abogado Demo',
        email: 'abogado@demo.com',
        password: '123456',
        rol: RolApp.abogado,
        fechaCreacion: now,
      ).toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      DatabaseHelper.tablaUsuarios,
      Usuario(
        nombre: 'Notificador Demo',
        email: 'notificador@demo.com',
        password: '123456',
        rol: RolApp.notificador,
        fechaCreacion: now,
      ).toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Usuario?> login({required String email, required String password}) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseHelper.tablaUsuarios,
      where: 'email = ? AND password = ?',
      whereArgs: <Object>[email.trim().toLowerCase(), password],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return Usuario.fromMap(rows.first);
  }

  Future<Usuario> upsertLocalFromAppUser(AppUser appUser) async {
    final Database db = await _dbHelper.database;
    final String email = appUser.email.trim().toLowerCase();
    final RolApp rol = appUser.rol == UserRole.abogado
        ? RolApp.abogado
        : RolApp.notificador;

    final List<Map<String, Object?>> rows = await db.query(
      DatabaseHelper.tablaUsuarios,
      where: 'email = ?',
      whereArgs: <Object>[email],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final Map<String, Object?> row = rows.first;
      final int? id = row['id'] as int?;
      final Map<String, Object?> updated = <String, Object?>{
        'nombre': email.split('@').first,
        'rol': rol == RolApp.abogado ? 'abogado' : 'notificador',
        'group_id': appUser.groupId,
      };

      if (id != null) {
        await db.update(
          DatabaseHelper.tablaUsuarios,
          updated,
          where: 'id = ?',
          whereArgs: <Object>[id],
        );
      }

      return Usuario(
        id: id,
        nombre: updated['nombre'] as String,
        email: email,
        password: (row['password'] as String?) ?? '',
        rol: rol,
        fechaCreacion:
            DateTime.tryParse((row['fecha_creacion'] as String?) ?? '') ?? DateTime.now(),
        groupId: appUser.groupId,
      );
    }

    final DateTime now = DateTime.now();
    final Usuario nuevo = Usuario(
      nombre: email.split('@').first,
      email: email,
      password: '',
      rol: rol,
      fechaCreacion: now,
    );

    final int id = await db.insert(
      DatabaseHelper.tablaUsuarios,
      nuevo.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return Usuario(
      id: id,
      nombre: nuevo.nombre,
      email: nuevo.email,
      password: nuevo.password,
      rol: nuevo.rol,
      fechaCreacion: nuevo.fechaCreacion,
      groupId: appUser.groupId,
    );
  }
}

