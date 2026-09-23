import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final databaseServiceProvider = Provider((ref) => DatabaseService());

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'poletrace.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE poles (
        id TEXT PRIMARY KEY,
        pole_number TEXT,
        region TEXT,
        zone TEXT,
        ward TEXT,
        pole_old_lamp TEXT,
        lamp_type TEXT,
        latitude REAL,
        longitude REAL,
        distance_meters REAL,
        order_index INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pole_number TEXT,
        image_path TEXT,
        latitude REAL,
        longitude REAL,
        accuracy REAL,
        captured_at TEXT,
        status TEXT
      )
    ''');
  }

  // --- Pole Caching ---
  Future<void> cachePoles(List<Map<String, dynamic>> polesData) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM poles'); // Clear old cache
      for (var pole in polesData) {
        await txn.insert(
          'poles', 
          pole, 
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedPoles() async {
    final db = await database;
    return await db.query('poles', orderBy: 'order_index ASC');
  }

  // --- Sync Queue ---
  Future<int> addToSyncQueue(Map<String, dynamic> item) async {
    final db = await database;
    return await db.insert('sync_queue', item);
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return await db.query('sync_queue', where: 'status = ?', whereArgs: ['pending']);
  }

  Future<void> updateSyncItemStatus(int id, String status) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeSyncItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }
}
