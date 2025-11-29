import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/audio_file_model.dart';
import 'package:flutter/material.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'music_player.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE audio_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT UNIQUE NOT NULL,
        file_name TEXT NOT NULL,
        title TEXT,
        artist TEXT,
        album TEXT,
        genre TEXT,
        year INTEGER,
        track_number INTEGER,
        file_size INTEGER NOT NULL,
        file_extension TEXT NOT NULL,
        duration INTEGER NOT NULL,
        date_added INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        created_date INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE playlist_tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        audio_file_id INTEGER NOT NULL,
        track_order INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (audio_file_id) REFERENCES audio_files (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_audio_files_path ON audio_files(file_path)');
    await db.execute('CREATE INDEX idx_audio_files_artist ON audio_files(artist)');
    await db.execute('CREATE INDEX idx_audio_files_album ON audio_files(album)');
    await db.execute('CREATE INDEX idx_audio_files_genre ON audio_files(genre)');
  }

  Future<int> insertAudioFile(AudioFileModel audioFile) async {
    final db = await database;
    try {
      return await db.insert('audio_files', audioFile.toMap());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return await updateAudioFile(audioFile);
      }
      rethrow;
    }
  }

  Future<List<AudioFileModel>> getAudioFiles() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      orderBy: 'date_added DESC'
    );
    return List.generate(maps.length, (i) => AudioFileModel.fromMap(maps[i]));
  }

  Future<AudioFileModel?> getAudioFileByPath(String filePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    if (maps.isNotEmpty) {
      return AudioFileModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateAudioFile(AudioFileModel audioFile) async {
    final db = await database;
    return await db.update(
      'audio_files',
      audioFile.toMap(),
      where: 'file_path = ?',
      whereArgs: [audioFile.filePath],
    );
  }

  Future<int> deleteAudioFile(String filePath) async {
    final db = await database;
    return await db.delete(
      'audio_files',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  Future<List<AudioFileModel>> getAudioFilesByArtist(String artist) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      where: 'artist = ?',
      whereArgs: [artist],
      orderBy: 'album, track_number',
    );
    return List.generate(maps.length, (i) => AudioFileModel.fromMap(maps[i]));
  }

  Future<List<AudioFileModel>> getAudioFilesByAlbum(String album) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      where: 'album = ?',
      whereArgs: [album],
      orderBy: 'track_number',
    );
    return List.generate(maps.length, (i) => AudioFileModel.fromMap(maps[i]));
  }

  Future<List<String>> getArtists() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      columns: ['artist'],
      where: 'artist IS NOT NULL',
      distinct: true,
      orderBy: 'artist',
    );
    return maps.map((map) => map['artist'] as String).toList();
  }

  Future<List<String>> getAlbums() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      columns: ['album'],
      where: 'album IS NOT NULL',
      distinct: true,
      orderBy: 'album',
    );
    return maps.map((map) => map['album'] as String).toList();
  }

  Future<List<String>> getGenres() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audio_files',
      columns: ['genre'],
      where: 'genre IS NOT NULL',
      distinct: true,
      orderBy: 'genre',
    );
    return maps.map((map) => map['genre'] as String).toList();
  }
}