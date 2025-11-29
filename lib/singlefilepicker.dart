import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/player.dart';
import 'package:musicplayer/edit_tags_dialog.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/audio_player_service.dart';

class Singlefilepicker extends StatefulWidget {
  const Singlefilepicker({super.key});

  @override
  State<Singlefilepicker> createState() => _SinglefilepickerState();
}

class _SinglefilepickerState extends State<Singlefilepicker> {
  final AudioService _audioService = AudioService();
  final AudioPlayerService _playerService = AudioPlayerService();
  List<AudioFileModel> _audioFiles = [];
  bool isLoading = false;
  bool _isInitialized = false;
  
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioFileModel? _currentPlayingFile;
  Uint8List? _currentAlbumArt;

  @override
  void initState() {
    super.initState();
    _loadAudioFiles();
    _setupPlayerListeners();
    _audioService.addFileUpdateListener(_onFileUpdated);
  }

  @override
  void dispose() {
    _audioService.removeFileUpdateListener(_onFileUpdated);
    _playerService.removePlaybackListener(_playbackListener);
    _playerService.removePositionListener(_positionListener);
    _playerService.removeDurationListener(_durationListener);
    super.dispose();
  }

  void _setupPlayerListeners() {
    _playerService.addPlaybackListener(_playbackListener);
    _playerService.addPositionListener(_positionListener);
    _playerService.addDurationListener(_durationListener);
  }

  void _playbackListener(bool isPlaying) {
    if (mounted) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }
  }

  void _positionListener(Duration position) {
    if (mounted) {
      setState(() {
        _position = position;
      });
    }
  }

  void _durationListener(Duration duration) {
    if (mounted) {
      setState(() {
        _duration = duration;
      });
    }
  }

  void _onFileUpdated(String filePath) {
    if (mounted) {
      print("File updated: $filePath");
      _refreshAllData(); 
    }
  }

  Future<void> _refreshAllData() async {
    await _loadAudioFiles(); 
    
    if (_currentPlayingFile != null) {
      await _updateCurrentPlayingFileData();
    }
  }

  Future<void> _updateCurrentPlayingFileData() async {
    if (_currentPlayingFile == null) return;
    
    try {
      final updatedFile = _audioFiles.firstWhere(
        (file) => file.filePath == _currentPlayingFile!.filePath,
        orElse: () => _currentPlayingFile!,
      );
      
      final albumArt = await _audioService.getCover(_currentPlayingFile!.filePath);
      
      if (mounted) {
        setState(() {
          _currentPlayingFile = updatedFile;
          _currentAlbumArt = albumArt;
        });
        print("Current file data updated in mini player");
      }
    } catch (e) {
      print("Error updating current file data: $e");
    }
  }

  Future<void> _loadAudioFiles() async {
    if (!mounted) return;
    
    try {
      final files = await _audioService.getAudioFiles();
      if (mounted) {
        setState(() {
          _audioFiles = files;
          _isInitialized = true;
        });
      }
      print("Loaded ${_audioFiles.length} audio files");
    } catch (e) {
      print("Error loading audio files: $e");
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _loadCurrentFileData() async {
    if (_currentPlayingFile == null) return;
    
    try {
      final albumArt = await _audioService.getCover(_currentPlayingFile!.filePath);
      if (mounted) {
        setState(() {
          _currentAlbumArt = albumArt;
        });
      }
    } catch (e) {
      print("Error loading current file data: $e");
    }
  }

  Future<void> pickMultipleFiles() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.audio,
      );

      if (result != null) {
        List<PlatformFile> newFiles = result.files;
        
        newFiles = newFiles.where((file) {
          final extension = file.extension?.toLowerCase();
          return extension == 'mp3' || 
                 extension == 'wav' || 
                 extension == 'aac' || 
                 extension == 'm4a' ||
                 extension == 'ogg' ||
                 extension == 'flac';
        }).toList();

        await _audioService.addFiles(newFiles);
        await _refreshAllData();
      }
    } catch (e) {
      print("Error picking files: $e");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void playAudioFile(AudioFileModel audioFile) {
    setState(() {
      _currentPlayingFile = audioFile;
      _currentAlbumArt = null; 
    });
    _playCurrentFile();
    _loadCurrentFileData(); 
  }

  void _handlePlayPauseFromList(AudioFileModel audioFile) {
    final isCurrentFile = _currentPlayingFile?.filePath == audioFile.filePath;
    
    if (isCurrentFile && _isPlaying) {
      _playerService.pause();
    } else {
      playAudioFile(audioFile);
    }
  }

  void playAudioFileFullScreen(AudioFileModel audioFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleExampleApp(audioFile: audioFile),
      ),
    ).then((_) {
      _refreshAllData();
    });
  }

  Future<void> _playCurrentFile() async {
    if (_currentPlayingFile == null) return;

    try {
      await _playerService.playAudioFile(_currentPlayingFile!);
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
    if (_currentPlayingFile == null) {
      if (_audioFiles.isNotEmpty) {
        playAudioFile(_audioFiles.first);
      }
      return;
    }

    if (_isPlaying) {
      await _playerService.pause();
    } else {
      await _playerService.resume();
    }
  }

  Future<void> _playNext() async {
    if (_audioFiles.isEmpty || _currentPlayingFile == null) return;
    
    final currentIndex = _audioFiles.indexWhere((file) => file.filePath == _currentPlayingFile!.filePath);
    if (currentIndex == -1) return;
    
    final nextIndex = (currentIndex + 1) % _audioFiles.length;
    playAudioFile(_audioFiles[nextIndex]);
  }

  Future<void> _playPrevious() async {
    if (_audioFiles.isEmpty || _currentPlayingFile == null) return;
    
    final currentIndex = _audioFiles.indexWhere((file) => file.filePath == _currentPlayingFile!.filePath);
    if (currentIndex == -1) return;
    
    final prevIndex = currentIndex == 0 ? _audioFiles.length - 1 : currentIndex - 1;
    playAudioFile(_audioFiles[prevIndex]);
  }

  void removeFile(int index) async {
    final audioFile = _audioFiles[index];
    
    if (_currentPlayingFile?.filePath == audioFile.filePath) {
      await _playerService.stop();
      setState(() {
        _currentPlayingFile = null;
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
        _currentAlbumArt = null;
      });
    }
    
    await _audioService.removeFile(audioFile.filePath);
    await _refreshAllData();
  }

  Future<void> editTags(AudioFileModel audioFile, int index) async {
    final currentMetadata = await _audioService.getMetadata(audioFile.filePath);
    
    if (currentMetadata == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditTagsDialog(
        initialMetadata: currentMetadata,
        filePath: audioFile.filePath,
      ),
    );

    if (result == true) {
      await _audioService.refreshFileData(audioFile.filePath);
      await _refreshAllData(); 
      
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

  String _getCurrentFileTitle() {
    if (_currentPlayingFile == null) return '';
    return _currentPlayingFile!.title ?? 
           _currentPlayingFile!.fileName.replaceAll(
             RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
             ''
           );
  }

  String _getCurrentFileArtist() {
    if (_currentPlayingFile == null) return '';
    return _currentPlayingFile!.artist ?? 'Неизвестный исполнитель';
  }

  Widget _buildMiniPlayerAlbumArt() {
    if (_currentAlbumArt != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _currentAlbumArt!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildMiniPlayerPlaceholder();
          },
        ),
      );
    }
    return _buildMiniPlayerPlaceholder();
  }

  Widget _buildMiniPlayerPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.music_note, color: Colors.grey.shade600, size: 20),
    );
  }

  Widget _buildMiniPlayer() {
    if (_currentPlayingFile == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            minHeight: 2,
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  _buildMiniPlayerAlbumArt(),
                  
                  SizedBox(width: 12),
                  
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getCurrentFileTitle(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2),
                        Text(
                          _getCurrentFileArtist(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.skip_previous, size: 20),
                        onPressed: _playPrevious,
                        color: Colors.blue.shade600,
                        padding: EdgeInsets.all(4),
                        constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 16,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, size: 20),
                        onPressed: _playNext,
                        color: Colors.blue.shade600,
                        padding: EdgeInsets.all(4),
                        constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.fullscreen, size: 18),
                        onPressed: () => playAudioFileFullScreen(_currentPlayingFile!),
                        color: Colors.grey.shade600,
                        padding: EdgeInsets.all(4),
                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(255, 49, 168, 215),
                Color.fromARGB(255, 58, 207, 100)
              ]
            ),
          ),
        ),
        title: const Text(
          'Music Player',
          style: TextStyle(
            color: Color.fromARGB(255, 59, 54, 54),
            fontWeight: FontWeight.bold,
            fontSize: 25,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : pickMultipleFiles,
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  Color.fromARGB(255, 99, 198, 47)
                ),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 16, horizontal: 24)
                ),
              ),
              icon: isLoading 
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.audio_file),
              label: isLoading
                  ? Text('Загрузка...', style: TextStyle(fontSize: 20))
                  : Text('Выбрать аудио файлы', style: TextStyle(fontSize: 20)),
            ),
          ),
          
          Expanded(
            child: !_isInitialized 
                ? Center(child: CircularProgressIndicator())
                : _audioFiles.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _audioFiles.length,
                        itemBuilder: (context, index) {
                          final audioFile = _audioFiles[index];
                          final isCurrentPlaying = _currentPlayingFile?.filePath == audioFile.filePath;
                          
                          return AudioFileItem(
                            key: ValueKey('${audioFile.filePath}-$index'),
                            audioFile: audioFile,
                            audioService: _audioService,
                            isCurrentPlaying: isCurrentPlaying,
                            isPlaying: _isPlaying && isCurrentPlaying,
                            onPlay: () => _handlePlayPauseFromList(audioFile),
                            onRemove: () => removeFile(index),
                            onEdit: () => editTags(audioFile, index),
                          );
                        },
                      ),
          ),
          
          _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            size: 64,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 16),
          Text(
            'Нет загруженных аудио файлов',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Нажмите кнопку выше чтобы добавить музыку',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class AudioFileItem extends StatefulWidget {
  final AudioFileModel audioFile;
  final AudioService audioService;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final bool isCurrentPlaying;
  final bool isPlaying;

  const AudioFileItem({
    required this.audioFile,
    required this.audioService,
    required this.onPlay,
    required this.onRemove,
    required this.onEdit,
    this.isCurrentPlaying = false,
    this.isPlaying = false,
    super.key,
  });

  @override
  State<AudioFileItem> createState() => _AudioFileItemState();
}

class _AudioFileItemState extends State<AudioFileItem> {
  Uint8List? _albumArt;
  bool _isLoadingArt = true;

  @override
  void initState() {
    super.initState();
    _loadAlbumArt();
    widget.audioService.addFileUpdateListener(_onFileUpdated);
  }

  @override
  void dispose() {
    widget.audioService.removeFileUpdateListener(_onFileUpdated);
    super.dispose();
  }

  void _onFileUpdated(String filePath) {
    if (filePath == widget.audioFile.filePath && mounted) {
      _loadAlbumArt(); 
    }
  }

  Future<void> _loadAlbumArt() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingArt = true;
        });
      }
      
      final albumArt = await widget.audioService.getCover(widget.audioFile.filePath);
      
      if (mounted) {
        setState(() {
          _albumArt = albumArt;
          _isLoadingArt = false;
        });
      }
    } catch (e) {
      print("Error loading album art for ${widget.audioFile.fileName}: $e");
      if (mounted) {
        setState(() {
          _isLoadingArt = false;
        });
      }
    }
  }

  String getFileSize() {
    final bytes = widget.audioFile.fileSize;
    final kb = bytes / 1024;
    final mb = kb / 1024;
    return mb >= 1 
        ? '${mb.toStringAsFixed(2)} MB'
        : '${kb.toStringAsFixed(2)} KB';
  }

  String getTitle() {
    return widget.audioFile.title ??
           widget.audioFile.fileName.replaceAll(
             RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
             ''
           );
  }

  String getArtist() {
    return widget.audioFile.artist ?? 'Неизвестный исполнитель';
  }

  String getAlbum() {
    return widget.audioFile.album ?? '';
  }

  Widget _buildAlbumArt() {
    if (_isLoadingArt) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    
    if (_albumArt != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _albumArt!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholderIcon();
          },
        ),
      );
    }
    return _buildPlaceholderIcon();
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: widget.isCurrentPlaying ? Colors.green.shade100 : Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
        border: widget.isCurrentPlaying 
            ? Border.all(color: Colors.green, width: 2)
            : null,
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.music_note,
              color: widget.isCurrentPlaying ? Colors.green : Colors.blue.shade600,
              size: 24,
            ),
          ),
          if (widget.isPlaying && widget.isCurrentPlaying)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volume_up,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      color: widget.isCurrentPlaying ? Colors.green.shade50 : null,
      child: ListTile(
        leading: _buildAlbumArt(),
        title: Text(
          getTitle(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: widget.isCurrentPlaying ? Colors.green.shade800 : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              getArtist(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.isCurrentPlaying ? Colors.green.shade600 : null,
              ),
            ),
            if (getAlbum().isNotEmpty)
              Text(
                getAlbum(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12, 
                  color: widget.isCurrentPlaying ? Colors.green.shade500 : Colors.grey.shade600,
                ),
              ),
            Text(
              '${widget.audioFile.fileExtension.toUpperCase()} • ${getFileSize()}',
              style: TextStyle(
                fontSize: 11, 
                color: widget.isCurrentPlaying ? Colors.green.shade400 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isCurrentPlaying && widget.isPlaying)
              Icon(
                Icons.equalizer,
                color: Colors.green,
                size: 20,
              ),
            IconButton(
              icon: Icon(Icons.edit, color: Colors.blue),
              onPressed: widget.onEdit,
              tooltip: 'Редактировать теги',
            ),
            IconButton(
              icon: Icon(
                widget.isCurrentPlaying && widget.isPlaying ? Icons.pause : Icons.play_arrow, 
                color: Colors.green
              ),
              onPressed: widget.onPlay,
              tooltip: widget.isCurrentPlaying && widget.isPlaying ? 'Пауза' : 'Воспроизвести',
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: widget.onRemove,
              tooltip: 'Удалить',
            ),
          ],
        ),
        onTap: widget.onPlay,
      ),
    );
  }
}