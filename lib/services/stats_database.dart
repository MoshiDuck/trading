// lib/services/stats_database.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SourceStatsRecord {
  final int? id;
  final String sourceName;
  final bool success;
  final double responseTime;
  final DateTime timestamp;
  final String? error;
  final double reliability;
  final double consistency;

  SourceStatsRecord({
    this.id,
    required this.sourceName,
    required this.success,
    required this.responseTime,
    required this.timestamp,
    this.error,
    required this.reliability,
    required this.consistency,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source_name': sourceName,
      'success': success ? 1 : 0,
      'response_time': responseTime,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'error': error,
      'reliability': reliability,
      'consistency': consistency,
    };
  }

  factory SourceStatsRecord.fromMap(Map<String, dynamic> map) {
    return SourceStatsRecord(
      id: map['id'],
      sourceName: map['source_name'],
      success: map['success'] == 1,
      responseTime: map['response_time'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      error: map['error'],
      reliability: map['reliability'],
      consistency: map['consistency'],
    );
  }
}

class StatsDatabase {
  static final StatsDatabase _instance = StatsDatabase._internal();
  factory StatsDatabase() => _instance;
  StatsDatabase._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = join(await getDatabasesPath(), 'btc_stats.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE source_stats(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_name TEXT NOT NULL,
        success INTEGER NOT NULL,
        response_time REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        error TEXT,
        reliability REAL NOT NULL,
        consistency REAL NOT NULL
      )
    ''');

    // Index pour les requêtes par source et timestamp
    await db.execute('''
      CREATE INDEX idx_source_timestamp ON source_stats(source_name, timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_timestamp ON source_stats(timestamp)
    ''');
  }

  // Insérer un enregistrement de statistiques
  Future<int> insertStatsRecord(SourceStatsRecord record) async {
    final db = await database;
    return await db.insert('source_stats', record.toMap());
  }

  // Récupérer les statistiques d'une source sur une période
  Future<List<SourceStatsRecord>> getSourceStats(
      String sourceName, {
        Duration period = const Duration(hours: 24),
      }) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(period).millisecondsSinceEpoch;

    final List<Map<String, dynamic>> maps = await db.query(
      'source_stats',
      where: 'source_name = ? AND timestamp >= ?',
      whereArgs: [sourceName, cutoffTime],
      orderBy: 'timestamp DESC',
    );

    return maps.map((map) => SourceStatsRecord.fromMap(map)).toList();
  }

  // Récupérer toutes les statistiques récentes
  Future<List<SourceStatsRecord>> getAllRecentStats({
    Duration period = const Duration(hours: 24),
  }) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(period).millisecondsSinceEpoch;

    final List<Map<String, dynamic>> maps = await db.query(
      'source_stats',
      where: 'timestamp >= ?',
      whereArgs: [cutoffTime],
      orderBy: 'timestamp DESC',
    );

    return maps.map((map) => SourceStatsRecord.fromMap(map)).toList();
  }

  // Obtenir les statistiques agrégées pour l'UI
  Future<Map<String, dynamic>> getAggregatedStats({
    Duration period = const Duration(hours: 24),
  }) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(period).millisecondsSinceEpoch;

    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT 
        source_name,
        COUNT(*) as total_requests,
        SUM(success) as successful_requests,
        AVG(response_time) as avg_response_time,
        AVG(reliability) as avg_reliability,
        AVG(consistency) as avg_consistency,
        MAX(timestamp) as last_request
      FROM source_stats 
      WHERE timestamp >= ?
      GROUP BY source_name
    ''', [cutoffTime]);

    final stats = <String, dynamic>{};

    for (var row in result) {
      final total = row['total_requests'] as int;
      final successful = row['successful_requests'] as int;
      final successRate = total > 0 ? successful / total : 0.0;

      stats[row['source_name'] as String] = {
        'success': successful,
        'total': total,
        'successRate': successRate,
        'avgResponseTime': (row['avg_response_time'] as double?)?.toStringAsFixed(3) ?? '0.000',
        'avgReliability': (row['avg_reliability'] as double?)?.toStringAsFixed(3) ?? '0.000',
        'avgConsistency': (row['avg_consistency'] as double?)?.toStringAsFixed(3) ?? '0.000',
        'lastRequest': DateTime.fromMillisecondsSinceEpoch(row['last_request'] as int).toIso8601String(),
      };
    }

    return stats;
  }

  // Nettoyer les anciens enregistrements (garder 30 jours)
  Future<int> cleanupOldRecords() async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;

    return await db.delete(
      'source_stats',
      where: 'timestamp < ?',
      whereArgs: [cutoffTime],
    );
  }

  // Fermer la base de données
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}