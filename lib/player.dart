import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audiotags/audiotags.dart';
import 'package:musicplayer/edit_tags_dialog.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/audio_player_service.dart';

class SimpleExampleApp extends StatefulWidget {
  final AudioFileModel audioFile;
  const SimpleExampleApp({required this.audioFile, super.key});

  @override
  State<SimpleExampleApp> createState() => SimpleExampleAppState();
}

class SimpleExampleAppState extends State<SimpleExampleApp> {
  final AudioService _audioService = AudioService();
  final AudioPlayerService _playerService = AudioPlayerService();
  Tag? metadata;
  Uint8List? albumArt;
  bool isLoadingMetadata = true;
  
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playerReady = false;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _setupPlayerListeners();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_playerService.isInitialized) {
        _playerReady = true;
        _playCurrentFile();
      } else {
        _playerService.init();
        _playerReady = true;
        _playCurrentFile();
      }
    });
  }

  void _setupPlayerListeners() {
    _playerService.addPlaybackListener((isPlaying) {
      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    });

    _playerService.addPositionListener((position) {
      if (mounted && !_isSeeking) {
        setState(() {
          _position = position;
        });
      }
    });

    _playerService.addDurationListener((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  Future<void> _loadMetadata() async {
    try {
      await _audioService.forceRefreshMetadata(widget.audioFile.filePath);
      metadata = await _audioService.getMetadata(widget.audioFile.filePath);
      albumArt = await _audioService.getCover(widget.audioFile.filePath);
      
      if (mounted) {
        setState(() {
          isLoadingMetadata = false;
        });
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

  Future<void> _playCurrentFile() async {
    if (!_playerReady) {
      print("Player not ready yet");
      return;
    }

    try {
      await _playerService.playAudioFile(widget.audioFile);
      
      Future.delayed(Duration(seconds: 1), () {
        if (mounted && _duration == Duration.zero) {
          _playerService.refreshDuration();
        }
      });
    } catch (e) {
      print("Ошибка воспроизведения: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения файла: $e')),
        );
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_playerReady) return;

    if (_isPlaying) {
      await _playerService.pause();
    } else {
      if (_playerService.currentAudioFile?.filePath == widget.audioFile.filePath) {
        await _playerService.resume();
      } else {
        await _playCurrentFile();
      }
    }
  }

  Future<void> _stopFile() async {
    if (!_playerReady) return;
    await _playerService.stop();
  }

  Future<void> _seekTo(Duration position) async {
    if (!_playerReady) return;
    
    setState(() {
      _isSeeking = true;
    });
    
    try {
      await _playerService.seek(position);
      
      setState(() {
        _position = position;
      });
    } catch (e) {
      print("Error seeking: $e");
    } finally {
      setState(() {
        _isSeeking = false;
      });
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
    _playerService.removePlaybackListener((_) {});
    _playerService.removePositionListener((_) {});
    _playerService.removeDurationListener((_) {});
    super.dispose();
  }

  String getTitle() {
    if (isLoadingMetadata) return widget.audioFile.fileName;
    return metadata?.title ?? widget.audioFile.title ??
           _getFileNameWithoutExtension();
  }

  String _getFileNameWithoutExtension() {
    return widget.audioFile.fileName.replaceAll(
      RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
      ''
    );
  }

  String getArtist() {
    if (isLoadingMetadata) return 'Загрузка...';
    return metadata?.trackArtist ?? widget.audioFile.artist ?? 'Неизвестный исполнитель';
  }

  String getAlbum() {
    if (isLoadingMetadata) return '';
    return metadata?.album ?? widget.audioFile.album ?? 'Неизвестный альбом';
  }

  String? getYear() {
    if (isLoadingMetadata) return null;
    return metadata?.year?.toString() ?? (widget.audioFile.year?.toString());
  }

  String? getGenre() {
    if (isLoadingMetadata) return null;
    return metadata?.genre ?? widget.audioFile.genre;
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
    return IconButton(
      icon: Icon(
        _isPlaying ? Icons.pause : Icons.play_arrow,
        size: 48,
        color: Colors.green,
      ),
      onPressed: _togglePlayPause,
    );
  }

  Widget _buildProgressBar() {
    final maxDuration = _duration.inSeconds.toDouble();
    final currentPosition = _position.inSeconds.toDouble();

    if (maxDuration == 0) {
      return Column(
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position)),
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
            setState(() {
              _position = Duration(seconds: value.toInt());
            });
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
              Text(_formatDuration(_position)),
              Text(_formatDuration(_duration)),
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
                  else if (!_playerReady)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Инициализация плеера...'),
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
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Переход к предыдущему треку')),
            );
          },
        ),
        SizedBox(width: 20),
        IconButton(
          icon: Icon(Icons.stop, size: 32, color: Colors.red),
          onPressed: _stopFile,
        ),
        SizedBox(width: 20),
        IconButton(
          icon: Icon(Icons.skip_next, size: 32, color: Colors.blue),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Переход к следующему треку')),
            );
          },
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