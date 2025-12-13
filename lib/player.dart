import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audiotags/audiotags.dart';
import 'package:musicplayer/edit_tags_dialog.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/player_state_service.dart';
import 'package:provider/provider.dart';

class SimpleExampleApp extends StatefulWidget {
  final AudioFileModel audioFile;
  const SimpleExampleApp({required this.audioFile, super.key});

  @override
  State<SimpleExampleApp> createState() => SimpleExampleAppState();
}

class SimpleExampleAppState extends State<SimpleExampleApp> {
  final AudioService _audioService = AudioService();
  Tag? metadata;
  Uint8List? albumArt;
  bool isLoadingMetadata = true;
  bool _isSeeking = false;
  List<AudioFileModel> _allAudioFiles = [];
  PlayerStateService? _playerState; 
  AudioFileModel? _currentAudioFile; 

  @override
  void initState() {
    super.initState();
    _currentAudioFile = widget.audioFile;
    _loadMetadata();
    _loadAllAudioFiles();
    _setupPlayerStateListeners();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final playerState = Provider.of<PlayerStateService>(context, listen: false);
      _playerState = playerState; 
      if (playerState.currentPlayingFile?.filePath != _currentAudioFile!.filePath) {
        await playerState.playAudioFile(_currentAudioFile!);
      }
    });
  }

  Future<void> _loadAllAudioFiles() async {
    try {
      _allAudioFiles = await _audioService.getAudioFiles();
    } catch (e) {
      print("Error loading audio files: $e");
    }
  }

  void _setupPlayerStateListeners() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    _playerState = playerState;
    playerState.addListener(_onPlayerStateChanged);
  }

    void _onPlayerStateChanged() {
    if (mounted) {
      final currentFile = _playerState?.currentPlayingFile;
      if (currentFile != null && currentFile.filePath != _currentAudioFile?.filePath) {
        _currentAudioFile = currentFile;
        _loadMetadata();
      }
      setState(() {});
    }
  }

  Future<void> _loadMetadata() async {
    try {
      if (_currentAudioFile != null) {
        await _audioService.forceRefreshMetadata(_currentAudioFile!.filePath);
        metadata = await _audioService.getMetadata(_currentAudioFile!.filePath);
        albumArt = await _audioService.getCover(_currentAudioFile!.filePath);
        
        if (mounted) {
          setState(() {
            isLoadingMetadata = false;
          });
        }
      }
    } catch (e) {
      print("Error loading metadata in player: $e");
      if (mounted) {
        setState(() {
          isLoadingMetadata = false;
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    await _playerState?.togglePlayPause();
  }

  Future<void> _stopFile() async {
    await _playerState?.stop();
  }

  Future<void> _seekTo(Duration position) async {
    setState(() {
      _isSeeking = true;
    });
    
    try {
      await _playerState?.seek(position);
    } catch (e) {
      print("Error seeking: $e");
    } finally {
      setState(() {
        _isSeeking = false;
      });
    }
  }

  Future<void> _playNextTrack() async {
    if (_allAudioFiles.isEmpty || _playerState?.currentPlayingFile == null) return;
    
    final currentIndex = _allAudioFiles.indexWhere(
      (file) => file.filePath == _playerState!.currentPlayingFile!.filePath
    );
    
    if (currentIndex != -1) {
      final nextIndex = (currentIndex + 1) % _allAudioFiles.length;
      final nextFile = _allAudioFiles[nextIndex];
      await _playerState!.playAudioFile(nextFile);
    }
  }

  Future<void> _playPreviousTrack() async {
    if (_allAudioFiles.isEmpty || _playerState?.currentPlayingFile == null) return;
    
    final currentIndex = _allAudioFiles.indexWhere(
      (file) => file.filePath == _playerState!.currentPlayingFile!.filePath
    );
    
    if (currentIndex != -1) {
      final prevIndex = currentIndex == 0 ? _allAudioFiles.length - 1 : currentIndex - 1;
      final prevFile = _allAudioFiles[prevIndex];
      await _playerState!.playAudioFile(prevFile);
    }
  }

  Future<void> _editTags() async {
    if (metadata == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditTagsDialog(
        initialMetadata: metadata!,
        filePath: widget.audioFile.filePath,
      ),
    );

    if (result == true) {
      final audioService = AudioService();
      await audioService.refreshFileData(widget.audioFile.filePath);
      
      await _loadMetadata();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Теги успешно обновлены!')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _playerState?.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  String getTitle() {
    if (isLoadingMetadata) return _currentAudioFile?.fileName ?? '';
    return metadata?.title ?? _currentAudioFile?.title ??
           _getFileNameWithoutExtension();
  }

  String _getFileNameWithoutExtension() {
    return _currentAudioFile?.fileName.replaceAll(
      RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
      ''
    ) ?? '';
  }

  String getArtist() {
    if (isLoadingMetadata) return 'Загрузка...';
    return metadata?.trackArtist ?? _currentAudioFile?.artist ?? 'Неизвестный исполнитель';
  }

  String getAlbum() {
    if (isLoadingMetadata) return '';
    return metadata?.album ?? _currentAudioFile?.album ?? 'Неизвестный альбом';
  }

  String? getYear() {
    if (isLoadingMetadata) return null;
    return metadata?.year?.toString() ?? (_currentAudioFile?.year?.toString());
  }

  String? getGenre() {
    if (isLoadingMetadata) return null;
    return metadata?.genre ?? _currentAudioFile?.genre;
  }

  Widget _buildAlbumArt() {
    if (albumArt != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          albumArt!,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholderAlbumArt();
          },
        ),
      );
    }
    return _buildPlaceholderAlbumArt();
  }

  Widget _buildPlaceholderAlbumArt() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade300, Colors.purple.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.music_note,
        color: Colors.white,
        size: 60,
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    final isPlaying = _playerState?.isPlaying ?? false;
    
    return IconButton(
      icon: Icon(
        isPlaying ? Icons.pause : Icons.play_arrow,
        size: 48,
        color: Colors.green,
      ),
      onPressed: _togglePlayPause,
    );
  }

  Widget _buildProgressBar() {
    final position = _playerState?.position ?? Duration.zero;
    final duration = _playerState?.duration ?? Duration.zero;
    
    final maxDuration = duration.inSeconds.toDouble();
    final currentPosition = position.inSeconds.toDouble();

    if (maxDuration == 0 || duration == Duration.zero) {
      return Column(
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position)),
                Text('--:--'),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Slider(
          min: 0,
          max: maxDuration,
          value: currentPosition.clamp(0, maxDuration),
          onChanged: (value) {
          },
          onChangeEnd: (value) {
            _seekTo(Duration(seconds: value.toInt()));
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLoadingMetadata ? 'Загрузка...' : 'Сейчас играет'),
        backgroundColor: Color.fromARGB(255, 47, 225, 121),
        elevation: 0,
        actions: [
          if (!isLoadingMetadata)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: _editTags,
              tooltip: 'Редактировать теги',
            ),
        ],
      ),
      body: Column(
        children: [
          if (!isLoadingMetadata)
            _buildMetadataCard(),
          
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoadingMetadata)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Загрузка метаданных...'),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildPlayPauseButton(),
                        SizedBox(height: 20),
                        _buildProgressBar(),
                        SizedBox(height: 20),
                        _buildControlButtons(),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous, size: 32, color: Colors.blue),
          onPressed: _playPreviousTrack, 
        ),
        SizedBox(width: 20),
        IconButton(
          icon: Icon(Icons.stop, size: 32, color: Colors.red),
          onPressed: _stopFile,
        ),
        SizedBox(width: 20),
        IconButton(
          icon: Icon(Icons.skip_next, size: 32, color: Colors.blue),
          onPressed: _playNextTrack, 
        ),
      ],
    );
  }

  Widget _buildMetadataCard() {
    final title = getTitle();
    final artist = getArtist();
    final album = getAlbum();

    return Container(
      margin: EdgeInsets.all(20),
      child: Column(
        children: [
          _buildAlbumArt(),
          SizedBox(height: 20),
          
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          
          Text(
            artist,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4),
          
          Text(
            album,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          if (getYear() != null) ...[
            SizedBox(height: 4),
            Text(
              'Год: ${getYear()}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],

          if (getGenre() != null) ...[
            SizedBox(height: 2),
            Text(
              'Жанр: ${getGenre()}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],

          if (widget.audioFile.trackNumber != null) ...[
            SizedBox(height: 2),
            Text(
              'Трек №${widget.audioFile.trackNumber}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}