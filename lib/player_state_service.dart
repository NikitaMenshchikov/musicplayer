import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_player_service.dart';
import 'package:musicplayer/audio_service.dart';

class PlayerStateService extends ChangeNotifier {
  final AudioPlayerService _playerService = AudioPlayerService();
  final AudioService _audioService = AudioService();
  
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioFileModel? _currentPlayingFile;
  Uint8List? _currentAlbumArt;
  bool _autoPlayNext = true;

  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioFileModel? get currentPlayingFile => _currentPlayingFile;
  Uint8List? get currentAlbumArt => _currentAlbumArt;
  bool get autoPlayNext => _autoPlayNext;

  final List<Function()> _completionListeners = [];

  PlayerStateService() {
    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    _playerService.addPlaybackListener(_playbackListener);
    _playerService.addPositionListener(_positionListener);
    _playerService.addDurationListener(_durationListener);
    _playerService.addCompletionListener(_completionListener); 
  }

  void _playbackListener(bool isPlaying) {
    _isPlaying = isPlaying;
    notifyListeners();
  }

  void _positionListener(Duration position) {
    _position = position;
    notifyListeners();
  }

  void _durationListener(Duration duration) {
    _duration = duration;
    notifyListeners();
  }

  void _completionListener() {
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
    
    if (_autoPlayNext) {
      _notifyCompletionListeners();
    }
  }

    Future<void> playAudioFileWithForceUpdate(AudioFileModel audioFile) async {
      
      _currentPlayingFile = audioFile;
      _currentAlbumArt = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      
      notifyListeners();
      
      await Future.delayed(Duration(milliseconds: 50));
      
      await _playerService.playAudioFile(audioFile);
      
      _loadAlbumArt();
  }

  Future<void> playAudioFile(AudioFileModel audioFile) async {
    
    _currentPlayingFile = audioFile;
    _currentAlbumArt = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    
    notifyListeners();
    await Future.delayed(Duration(milliseconds: 10));
    notifyListeners();
    
    await _playerService.playAudioFile(audioFile);
    _loadAlbumArt();
  }

  void forceRefresh() {
    notifyListeners();
  }



Future<void> _loadAlbumArt() async {
  if (_currentPlayingFile == null) return;
  
  try {
    final albumArt = await _audioService.getCover(_currentPlayingFile!.filePath);
    _currentAlbumArt = albumArt;
    notifyListeners();
  } catch (e) {
    notifyListeners();
  }
}

  void updateCurrentFile(AudioFileModel newFile) {
    _currentPlayingFile = newFile;
    _currentAlbumArt = null; 
    _loadAlbumArt(); 
    notifyListeners();
  }

  
Future<void> refreshCurrentFile() async {
  if (_currentPlayingFile == null) return;
  
  try {
    await _audioService.forceRefreshMetadata(_currentPlayingFile!.filePath);
    
    final tag = await _audioService.getMetadata(_currentPlayingFile!.filePath);
    final updatedAlbumArt = await _audioService.getCover(_currentPlayingFile!.filePath);
    
    if (tag != null) {
      _currentPlayingFile = AudioFileModel(
        id: _currentPlayingFile!.id,
        filePath: _currentPlayingFile!.filePath,
        fileName: _currentPlayingFile!.fileName,
        title: tag.title,
        artist: tag.trackArtist,
        album: tag.album,
        genre: tag.genre,
        year: tag.year,
        trackNumber: tag.trackNumber,
        fileSize: _currentPlayingFile!.fileSize,
        fileExtension: _currentPlayingFile!.fileExtension,
        duration: _currentPlayingFile!.duration,
        dateAdded: _currentPlayingFile!.dateAdded,
      );
      
      _currentAlbumArt = updatedAlbumArt;
      
      notifyListeners();
    }
  } catch (e) {
    print("fa");
  }
}

void syncWithAudioService() {
  if (_currentPlayingFile != null) {
    _loadAlbumArt();
    
    notifyListeners();
  }
}

    void refreshCurrentFileFromList(List<AudioFileModel> files) {
    if (_currentPlayingFile == null) return;
    
    final currentFilePath = _currentPlayingFile!.filePath;
    final updatedFile = files.firstWhere(
      (file) => file.filePath == currentFilePath,
      orElse: () => _currentPlayingFile!,
    );
    
    if (updatedFile != _currentPlayingFile) {
      updateCurrentFile(updatedFile);
    }
  }


  Future<void> togglePlayPause() async {
    if (_currentPlayingFile == null) return;
    
    if (_isPlaying) {
      await _playerService.pause();
    } else {
      await _playerService.resume();
    }
  }

  void setAutoPlayNext(bool value) {
    _autoPlayNext = value;
    notifyListeners();
  }

  Future<void> stop() async {
    await _playerService.stop();
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _playerService.seek(position);
    _position = position;
    notifyListeners();
  }

  void addCompletionListener(Function() listener) {
    _completionListeners.add(listener);
  }

  void removeCompletionListener(Function() listener) {
    _completionListeners.remove(listener);
  }

  void _notifyCompletionListeners() {
    for (final listener in _completionListeners) {
      listener();
    }
  }

  void refresh() {
    notifyListeners();
  }

  @override
  void dispose() {
    _playerService.removePlaybackListener(_playbackListener);
    _playerService.removePositionListener(_positionListener);
    _playerService.removeDurationListener(_durationListener);
    _playerService.removeCompletionListener(_completionListener);
    _completionListeners.clear();
    super.dispose();
  }
}