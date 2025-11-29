import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:audiotags/audiotags.dart';
import 'package:musicplayer/database/database_helper.dart';
import 'package:musicplayer/models/audio_file_model.dart';

class AudioService {
static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final Map<String, Tag?> _metadataCache = {};
  final Map<String, Uint8List?> _coverCache = {};

  final List<Function(String)> _fileUpdateListeners = [];

  void addFileUpdateListener(Function(String) listener) {
    _fileUpdateListeners.add(listener);
  }

  void removeFileUpdateListener(Function(String) listener) {
    _fileUpdateListeners.remove(listener);
  }

  void _notifyFileUpdated(String filePath) {
    for (final listener in _fileUpdateListeners) {
      listener(filePath);
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
    final filePath = platformFile.path!;
    
    var existingFile = await _databaseHelper.getAudioFileByPath(filePath);
    
    if (existingFile == null) {
      final tag = await _loadMetadataFromFile(filePath);
      final duration = await _getAudioDuration(filePath);
      
      final audioFileModel = AudioFileModel(
        filePath: filePath,
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
      
      if (tag != null) {
        _metadataCache[filePath] = tag;
        _updateCoverCache(filePath, tag.pictures);
      }
    } else {
      await _loadMetadataFromFile(filePath);
    }
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
      return Duration.zero;
    } catch (e) {
      print("Error getting audio duration for $filePath: $e");
      return null;
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