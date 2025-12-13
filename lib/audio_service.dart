import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart' hide AudioPlayer;
import 'package:file_picker/file_picker.dart';
import 'package:audiotags/audiotags.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musicplayer/database/database_helper.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/utils/path_utils.dart';

class AudioService {
static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final Map<String, Tag?> _metadataCache = {};
  final Map<String, Uint8List?> _coverCache = {};

  final List<Function(String)> _fileUpdateListeners = [];
  bool _isDisposed = false;
  void dispose() {
    _isDisposed = true;
    _fileUpdateListeners.clear();
  }

  void addFileUpdateListener(Function(String) listener) {
    _fileUpdateListeners.add(listener);
  }

  void removeFileUpdateListener(Function(String) listener) {
    _fileUpdateListeners.remove(listener);
  }

  void _notifyFileUpdated(String filePath) {
    if (_isDisposed) return;
    
    final listeners = List<Function(String)>.from(_fileUpdateListeners);
    
    for (final listener in listeners) {
      try {
        if (!_isDisposed) {
          listener(filePath);
        }
      } catch (e) {
        print("Error in file update listener: $e");
      }
    }
  }

  final List<Function(String)> _metadataUpdateListeners = [];

  void addMetadataUpdateListener(Function(String) listener) {
    _metadataUpdateListeners.add(listener);
  }

  void removeMetadataUpdateListener(Function(String) listener) {
    _metadataUpdateListeners.remove(listener);
  }

  void _notifyMetadataUpdated(String filePath) {
    for (final listener in _metadataUpdateListeners) {
      listener(filePath);
    }
  }

  Future<void> addFiles(List<PlatformFile> platformFiles) async {
    for (final platformFile in platformFiles) {
      if (platformFile.path != null) {
        await _processAudioFile(platformFile);
      }
    }
  }

Future<void> _processAudioFile(PlatformFile platformFile) async {
  final tempPath = platformFile.path!;
  final fileName = platformFile.name;
  
  print("Обработка файла: $fileName");
  print("Временный путь: $tempPath");
  
  String? permanentPath = await PathUtils.findOriginalPath(tempPath, fileName);
  
  if (permanentPath == null) {
    print("Не найден оригинальный файл для: $fileName");
    permanentPath = tempPath;
  } else {
    print("Найден оригинальный путь: $permanentPath");
  }
  
  var existingFile = await _databaseHelper.getAudioFileByPath(permanentPath);
  
  if (existingFile != null) {
    print("Файл уже в базе: $fileName");
    return;
  }
  
  final tag = await _loadMetadataFromFile(permanentPath);
  final duration = await _getAudioDuration(permanentPath);
  
  final audioFileModel = AudioFileModel(
    filePath: permanentPath,  
    fileName: platformFile.name,
    title: tag?.title,
    artist: tag?.trackArtist,
    album: tag?.album,
    genre: tag?.genre,
    year: tag?.year,
    trackNumber: tag?.trackNumber,
    fileSize: platformFile.size,
    fileExtension: platformFile.extension ?? 'unknown',
    duration: duration?.inMilliseconds ?? 0,
    dateAdded: DateTime.now(),
  );
  
  await _databaseHelper.insertAudioFile(audioFileModel);
  print("Файл добавлен в БД: $fileName");
}

Future<void> migrateTempPathsToPermanent() async {
  print("Начинаем миграцию временных путей...");
  
  final files = await _databaseHelper.getAudioFiles();
  int migratedCount = 0;
  int failedCount = 0;
  
  for (final file in files) {
    if (PathUtils.isTemporaryPath(file.filePath)) {
      print("Найден временный путь: ${file.filePath}");
      
      final originalPath = await PathUtils.findOriginalPath(
        file.filePath, 
        file.fileName
      );
      
      if (originalPath != null && originalPath != file.filePath) {
        try {
          final updatedFile = AudioFileModel(
            id: file.id,
            filePath: originalPath,
            fileName: file.fileName,
            title: file.title,
            artist: file.artist,
            album: file.album,
            genre: file.genre,
            year: file.year,
            trackNumber: file.trackNumber,
            fileSize: file.fileSize,
            fileExtension: file.fileExtension,
            duration: file.duration,
            dateAdded: file.dateAdded,
          );
          
          await _databaseHelper.updateAudioFile(updatedFile);
          migratedCount++;
          print("Мигрирован: ${file.fileName}");
        } catch (e) {
          failedCount++;
          print("Ошибка миграции ${file.fileName}: $e");
        }
      } else {
        print("Оригинал не найден для: ${file.fileName}");
        failedCount++;
      }
    }
  }
  
  print("Миграция завершена!");
  print("Успешно: $migratedCount, Не удалось: $failedCount");
}

Future<void> updateAudioFilePath(int id, String newFilePath) async {
  try {
    final files = await _databaseHelper.getAudioFiles();
    final file = files.firstWhere((f) => f.id == id);
    
    final updatedFile = AudioFileModel(
      id: file.id,
      filePath: newFilePath,
      fileName: file.fileName,
      title: file.title,
      artist: file.artist,
      album: file.album,
      genre: file.genre,
      year: file.year,
      trackNumber: file.trackNumber,
      fileSize: file.fileSize,
      fileExtension: file.fileExtension,
      duration: file.duration,
      dateAdded: file.dateAdded,
    );
    
    await _databaseHelper.updateAudioFile(updatedFile);
    
    clearFileCache(newFilePath);
    print("Обновлен путь файла: ${file.fileName} -> $newFilePath");
  } catch (e) {
    print("Ошибка обновления пути файла: $e");
    rethrow;
  }
}

Future<String?> _tryGetOriginalPath(String filePickerPath) async {

  return null; 
}
  Future<Tag?> _loadMetadataFromFile(String filePath) async {
    try {
      final tag = await AudioTags.read(filePath);
      _metadataCache[filePath] = tag;
      _updateCoverCache(filePath, tag?.pictures);
      return tag;
    } catch (e) {
      print("Error loading metadata for $filePath: $e");
      return null;
    }
  }

  void _updateCoverCache(String filePath, List<Picture>? pictures) {
    try {
      if (pictures != null && pictures.isNotEmpty) {
        _coverCache[filePath] = pictures.first.bytes;
      } else {
        _coverCache[filePath] = null;
      }
    } catch (e) {
      print("Error updating cover cache for $filePath: $e");
      _coverCache[filePath] = null;
    }
  }

Future<Duration?> _getAudioDuration(String filePath) async {
  try {
    final player = AudioPlayer();
    
    try {
      await player.setAudioSource(AudioSource.uri(Uri.file(filePath)));
      
      final duration = player.duration;
      
      await player.dispose();
      
      print("Duration for $filePath: $duration");
      return duration ?? Duration.zero;
    } catch (e) {
      print("Error getting duration with just_audio: $e");
      await player.dispose();
      return Duration.zero;
    }
  } catch (e) {
    print("Error getting audio duration for $filePath: $e");
    return Duration.zero;
  }
}

Future<void> recalculateDurations() async {
  try {
    final files = await _databaseHelper.getAudioFiles();
    
    for (final file in files) {
      if (file.duration <= 0) {
        final newDuration = await _getAudioDuration(file.filePath);
        if (newDuration != null && newDuration.inMilliseconds > 0) {
          final updatedFile = AudioFileModel(
            id: file.id,
            filePath: file.filePath,
            fileName: file.fileName,
            title: file.title,
            artist: file.artist,
            album: file.album,
            genre: file.genre,
            year: file.year,
            trackNumber: file.trackNumber,
            fileSize: file.fileSize,
            fileExtension: file.fileExtension,
            duration: newDuration.inMilliseconds,
            dateAdded: file.dateAdded,
          );
          
          await _databaseHelper.updateAudioFile(updatedFile);
          print("Updated duration for ${file.fileName}: $newDuration");
        }
      }
    }
  } catch (e) {
    print("Error recalculating durations: $e");
  }
}

  Future<List<AudioFileModel>> getAudioFiles() async {
    return await _databaseHelper.getAudioFiles();
  }

  Future<void> removeFile(String filePath) async {
    await _databaseHelper.deleteAudioFile(filePath);
    _metadataCache.remove(filePath);
    _coverCache.remove(filePath);
    _notifyMetadataUpdated(filePath);
  }

  Future<Tag?> getMetadata(String filePath) async {
    if (_metadataCache.containsKey(filePath)) {
      return _metadataCache[filePath];
    }
    return await _loadMetadataFromFile(filePath);
  }

  Future<Uint8List?> getCover(String filePath) async {
    if (_coverCache.containsKey(filePath)) {
      return _coverCache[filePath];
    }
    await _loadMetadataFromFile(filePath);
    return _coverCache[filePath];
  }

Future<void> updateMetadata(String filePath, Tag newMetadata, {List<Picture>? pictures}) async {
  try {
    await AudioTags.write(
      filePath,
      newMetadata    );
    
    _metadataCache.remove(filePath);
    _coverCache.remove(filePath);
    
    await _loadMetadataFromFile(filePath);
    
    final updatedTag = _metadataCache[filePath];
    
    final existingFile = await _databaseHelper.getAudioFileByPath(filePath);
    if (existingFile != null && updatedTag != null) {
      final updatedFile = AudioFileModel(
        id: existingFile.id,
        filePath: existingFile.filePath,
        fileName: existingFile.fileName,
        title: updatedTag.title,
        artist: updatedTag.trackArtist,
        album: updatedTag.album,
        genre: updatedTag.genre,
        year: updatedTag.year,
        trackNumber: updatedTag.trackNumber,
        fileSize: existingFile.fileSize,
        fileExtension: existingFile.fileExtension,
        duration: existingFile.duration,
        dateAdded: existingFile.dateAdded,
      );
      
      await _databaseHelper.updateAudioFile(updatedFile);
    }
    
    _notifyMetadataUpdated(filePath);
    _notifyFileUpdated(filePath); 

  } catch (e) {
    print("Error updating metadata for $filePath: $e");
    rethrow;
  }
}

Future<void> refreshFileData(String filePath) async {
  _metadataCache.remove(filePath);
  _coverCache.remove(filePath);
  
  await _loadMetadataFromFile(filePath);
  
  final existingFile = await _databaseHelper.getAudioFileByPath(filePath);
  if (existingFile != null) {
    final tag = _metadataCache[filePath];
    if (tag != null) {
      final updatedFile = AudioFileModel(
        id: existingFile.id,
        filePath: existingFile.filePath,
        fileName: existingFile.fileName,
        title: tag.title,
        artist: tag.trackArtist,
        album: tag.album,
        genre: tag.genre,
        year: tag.year,
        trackNumber: tag.trackNumber,
        fileSize: existingFile.fileSize,
        fileExtension: existingFile.fileExtension,
        duration: existingFile.duration,
        dateAdded: existingFile.dateAdded,
      );
      
      await _databaseHelper.updateAudioFile(updatedFile);
    }
  }
  
  _notifyMetadataUpdated(filePath);
  _notifyFileUpdated(filePath); 
}

Future<void> forceRefreshMetadata(String filePath) async {
  _metadataCache.remove(filePath);
  _coverCache.remove(filePath);
  
  await _loadMetadataFromFile(filePath);
}

  Future<List<AudioFileModel>> getAudioFilesWithRefresh() async {
    try {
      final files = await _databaseHelper.getAudioFiles();
      
      final updatedFiles = <AudioFileModel>[];
      
      for (final file in files) {
        try {
          await _loadMetadataFromFile(file.filePath);
          final tag = _metadataCache[file.filePath];
          
          if (tag != null) {
            final updatedFile = AudioFileModel(
              id: file.id,
              filePath: file.filePath,
              fileName: file.fileName,
              title: tag.title,
              artist: tag.trackArtist,
              album: tag.album,
              genre: tag.genre,
              year: tag.year,
              trackNumber: tag.trackNumber,
              fileSize: file.fileSize,
              fileExtension: file.fileExtension,
              duration: file.duration,
              dateAdded: file.dateAdded,
            );
            updatedFiles.add(updatedFile);
          } else {
            updatedFiles.add(file);
          }
        } catch (e) {
          print("Error refreshing metadata for ${file.fileName}: $e");
          updatedFiles.add(file);
        }
      }
      
      return updatedFiles;
    } catch (e) {
      print("Error getting audio files with refresh: $e");
      return await _databaseHelper.getAudioFiles();
    }
  }

  

  Future<List<String>> getArtists() async {
    return await _databaseHelper.getArtists();
  }

  Future<List<String>> getAlbums() async {
    return await _databaseHelper.getAlbums();
  }

  Future<List<String>> getGenres() async {
    return await _databaseHelper.getGenres();
  }

  Future<List<AudioFileModel>> getAudioFilesByArtist(String artist) async {
    return await _databaseHelper.getAudioFilesByArtist(artist);
  }

  Future<List<AudioFileModel>> getAudioFilesByAlbum(String album) async {
    return await _databaseHelper.getAudioFilesByAlbum(album);
  }

  void clearCache() {
    _metadataCache.clear();
    _coverCache.clear();
  }

void clearFileCache(String filePath) {
  _metadataCache.remove(filePath);
  _coverCache.remove(filePath);
}
}