import 'package:audioplayers/audioplayers.dart';
import 'package:musicplayer/models/audio_file_model.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  late AudioPlayer _player;
  AudioFileModel? _currentAudioFile;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isInitialized = false;

  AudioPlayer get player => _player;
  AudioFileModel? get currentAudioFile => _currentAudioFile;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isInitialized => _isInitialized;

  final List<Function(bool)> _playbackListeners = [];
  final List<Function(Duration)> _positionListeners = [];
  final List<Function(Duration)> _durationListeners = [];

  void init() {
    if (_isInitialized) return;
    
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.stop);

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _notifyPlaybackListeners();
    });

    _player.onDurationChanged.listen((duration) {
      _duration = duration;
      _notifyDurationListeners();
    });

    _player.onPositionChanged.listen((position) {
      _position = position;
      _notifyPositionListeners();
    });

    _player.onPlayerComplete.listen((event) {
      _isPlaying = false;
      _position = Duration.zero;
      _notifyPlaybackListeners();
      _notifyPositionListeners();
    });

    _isInitialized = true;
  }

  Future<void> playAudioFile(AudioFileModel audioFile) async {
    if (!_isInitialized) {
      print("AudioPlayerService not initialized");
      return;
    }

    try {
      if (_currentAudioFile?.filePath != audioFile.filePath) {
        await _player.stop();
        _position = Duration.zero;
        _duration = Duration.zero; 
        _notifyPositionListeners();
        _notifyDurationListeners();
        
        await _player.setSource(DeviceFileSource(audioFile.filePath));
        _currentAudioFile = audioFile;
        
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      await _player.resume();
    } catch (e) {
      print("Error playing audio file: $e");
      rethrow;
    }
  }

  Future<void> pause() async {
    if (!_isInitialized) return;
    await _player.pause();
  }

  Future<void> resume() async {
    if (!_isInitialized || _currentAudioFile == null) return;
    await _player.resume();
  }

  Future<void> stop() async {
    if (!_isInitialized) return;
    await _player.stop();
    _position = Duration.zero;
    _notifyPositionListeners();
  }

  Future<void> seek(Duration position) async {
    if (!_isInitialized) return;
    
    if (_duration != Duration.zero && position > _duration) {
      position = _duration;
    }
    
    await _player.seek(position);
  }

  Future<void> refreshDuration() async {
    if (!_isInitialized) return;
    
    try {
      final duration = await _player.getDuration();
      if (duration != null) {
        _duration = duration;
        _notifyDurationListeners();
      }
    } catch (e) {
      print("Error refreshing duration: $e");
    }
  }

  void addPlaybackListener(Function(bool) listener) {
    _playbackListeners.add(listener);
  }

  void removePlaybackListener(Function(bool) listener) {
    _playbackListeners.remove(listener);
  }

  void addPositionListener(Function(Duration) listener) {
    _positionListeners.add(listener);
  }

  void removePositionListener(Function(Duration) listener) {
    _positionListeners.remove(listener);
  }

  void addDurationListener(Function(Duration) listener) {
    _durationListeners.add(listener);
  }

  void removeDurationListener(Function(Duration) listener) {
    _durationListeners.remove(listener);
  }

  void _notifyPlaybackListeners() {
    for (final listener in _playbackListeners) {
      listener(_isPlaying);
    }
  }

  void _notifyPositionListeners() {
    for (final listener in _positionListeners) {
      listener(_position);
    }
  }

  void _notifyDurationListeners() {
    for (final listener in _durationListeners) {
      listener(_duration);
    }
  }

  void dispose() {
    if (_isInitialized) {
      _player.dispose();
    }
    _playbackListeners.clear();
    _positionListeners.clear();
    _durationListeners.clear();
    _isInitialized = false;
  }
}