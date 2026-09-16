import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/pole_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('poles.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';

    await db.execute('''
CREATE TABLE poles (
  id $idType,
  pole_number $textType,
  region $textType,
  zone $textType,
  ward $textType,
  pole_old_lamp $textType,
  lamp_type $textType,
  latitude $realType,
  longitude $realType
)
''');

    await db.execute('''
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pole_number $textType,
  image_path $textType,
  image_slot INTEGER NOT NULL,
  status $textType
)
''');
  }

  Future<void> cachePoles(List<Pole> poles) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var pole in poles) {
      batch.insert(
        'poles',
        {
          'id': pole.id,
          'pole_number': pole.poleNumber,
          'region': pole.region,
          'zone': pole.zone,
          'ward': pole.ward,
          'pole_old_lamp': pole.poleOldLamp,
          'lamp_type': pole.lampType,
          'latitude': pole.latitude,
          'longitude': pole.longitude,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Pole>> getCachedPoles({
    String? region,
    String? zone,
    String? ward,
    String? poleOldLamp,
    String? lampType,
  }) async {
    final db = await instance.database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (region != null && region.isNotEmpty) {
      whereClause += ' AND region = ?';
      whereArgs.add(region);
    }
    if (zone != null && zone.isNotEmpty) {
      whereClause += ' AND zone = ?';
      whereArgs.add(zone);
    }
    if (ward != null && ward.isNotEmpty) {
      whereClause += ' AND ward = ?';
      whereArgs.add(ward);
    }
    if (poleOldLamp != null && poleOldLamp.isNotEmpty) {
      whereClause += ' AND pole_old_lamp = ?';
      whereArgs.add(poleOldLamp);
    }
    if (lampType != null && lampType.isNotEmpty) {
      whereClause += ' AND lamp_type = ?';
      whereArgs.add(lampType);
    }

    final result = await db.query(
      'poles',
      where: whereClause,
      whereArgs: whereArgs,
    );

    return result.map((json) => Pole.fromJson(json)).toList();
  }

  // Pending Sync Queue Methods
  Future<void> addPendingUpload(String poleNumber, String imagePath, int imageSlot) async {
    final db = await instance.database;
    await db.insert('sync_queue', {
      'pole_number': poleNumber,
      'image_path': imagePath,
      'image_slot': imageSlot,
      'status': 'pending'
    });
  }

  Future<List<Map<String, dynamic>>> getPendingUploads() async {
    final db = await instance.database;
    return await db.query('sync_queue', where: 'status = ?', whereArgs: ['pending']);
  }

  Future<void> markUploadComplete(int id) async {
    final db = await instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }
}
