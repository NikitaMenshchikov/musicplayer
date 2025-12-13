import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:musicplayer/player.dart';
import 'package:musicplayer/edit_tags_dialog.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:musicplayer/player_state_service.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

class Singlefilepicker extends StatefulWidget {
  const Singlefilepicker({super.key});

  @override
  State<Singlefilepicker> createState() => _SinglefilepickerState();
}

class _SinglefilepickerState extends State<Singlefilepicker> {
  final AudioService _audioService = AudioService();
  final Logger _logger = Logger();
  
  List<AudioFileModel> _audioFiles = [];
  bool isLoading = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _logger.i("Singlefilepicker init");
    _loadAudioFiles();
    _setupCompletionListener();
    _audioService.addFileUpdateListener(_onParentFileUpdated);
    _checkPermissions();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _removeCompletionListener();
    _audioService.removeFileUpdateListener(_onParentFileUpdated);
    super.dispose();
  }

  void _setupCompletionListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playerState = Provider.of<PlayerStateService>(context, listen: false);
      playerState.addCompletionListener(_onTrackCompletion);
    });
  }

  void _removeCompletionListener() {
    try {
      if (mounted) {
        final playerState = Provider.of<PlayerStateService>(context, listen: false);
        playerState.removeCompletionListener(_onTrackCompletion);
      }
    } catch (e) {
      _logger.e("Error removing completion listener: $e");
    }
  }

  void _onTrackCompletion() {
    if (!mounted || _isDisposed) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed && _audioFiles.isNotEmpty) {
        _playNext();
      }
    });
  }

  void _onParentFileUpdated(String filePath) {
    _logger.d("Parent file updated: $filePath");
    if (!_isDisposed && mounted) {
      _loadAudioFiles();
    }
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        if (deviceInfo.version.sdkInt >= 33) {
          if (!await Permission.audio.isGranted) {
            await Permission.audio.request();
          }
        } else {
          if (!await Permission.storage.isGranted) {
            await Permission.storage.request();
          }
        }
      } catch (e) {
        _logger.e("Error checking permissions: $e");
      }
    }
  }

  Future<void> _loadAudioFiles() async {
    if (!mounted || _isDisposed) return;
    
    try {
      _logger.i("Loading audio files from database");
      final files = await _audioService.getAudioFiles();
      
      if (!mounted || _isDisposed) return;
      
      final validFiles = <AudioFileModel>[];
      
      for (final file in files) {
        try {
          final fileObj = File(file.filePath);
          final exists = await fileObj.exists();
          
          if (exists) {
            validFiles.add(file);
          } else {
            _logger.w("File not found: ${file.filePath}");
            final markedFile = AudioFileModel(
              id: file.id,
              filePath: file.filePath,
              fileName: file.fileName,
              title: file.title != null ? "${file.title} (недоступен)" : "${file.fileName} (недоступен)",
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
            validFiles.add(markedFile);
          }
        } catch (e) {
          _logger.e("Error checking file ${file.filePath}: $e");
          validFiles.add(file);
        }
      }
      
      if (mounted) {
        setState(() {
          _audioFiles = validFiles;
          _isInitialized = true;
        });
      }
      
      _logger.i("Loaded ${validFiles.length} files");
      
    } catch (e) {
      _logger.e("Error loading audio files: $e");
      if (!mounted || _isDisposed) return;
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> pickMultipleFiles() async {
    _logger.i("Starting file picker");
    
    setState(() {
      isLoading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.audio,
        withData: false,
        allowCompression: false,
        lockParentWindow: true,
      );

      if (result != null && result.files.isNotEmpty) {
        _logger.i("Selected ${result.files.length} files");
        
        final processedFiles = <PlatformFile>[];
        
        for (final file in result.files) {
          if (file.path == null) continue;
          
          final extension = _getFileExtension(file.name);
          if (!_isSupportedAudioFormat(extension)) continue;
          
          processedFiles.add(file);
        }
        
        if (processedFiles.isNotEmpty) {
          _logger.i("Adding ${processedFiles.length} files to database");
          
          await _audioService.addFiles(processedFiles);
          
          await _loadAudioFiles();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Добавлено ${processedFiles.length} файлов'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      _logger.e("Error picking files: $e");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файлов: ${e.toString()}'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  String _getFileExtension(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  bool _isSupportedAudioFormat(String extension) {
    final supportedFormats = ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'];
    return supportedFormats.contains(extension.toLowerCase());
  }

  void playAudioFile(AudioFileModel audioFile) {
    _logger.i("Playing audio file: ${audioFile.fileName}");
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    playerState.playAudioFile(audioFile);
  }

  void _handlePlayPauseFromList(AudioFileModel audioFile) {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    final isCurrentFile = playerState.currentPlayingFile?.filePath == audioFile.filePath;
    
    if (isCurrentFile && playerState.isPlaying) {
      _logger.d("Pausing current file");
      playerState.togglePlayPause();
    } else {
      _logger.d("Playing new file");
      playAudioFile(audioFile);
    }
  }

  Future<void> removeFile(int index) async {
    if (index < 0 || index >= _audioFiles.length) return;
    
    final audioFile = _audioFiles[index];
    _logger.i("Removing file: ${audioFile.fileName}");
    
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    final isCurrentPlaying = playerState.currentPlayingFile?.filePath == audioFile.filePath;
    
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить из библиотеки?'),
        content: Text('Файл останется на устройстве, но будет удален из библиотеки приложения.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить'),
          ),
        ],
      ),
    );
    
    if (shouldDelete != true) return;
    
    try {
      if (isCurrentPlaying) {
        await playerState.stop();
      }
      
      await _audioService.removeFile(audioFile.filePath);
      
      await _loadAudioFiles();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл удален из библиотеки'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      _logger.e("Error removing file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


Future<void> editTags(AudioFileModel audioFile, int index) async {
  _logger.i("Editing tags for: ${audioFile.fileName}");
  
  try {
    final file = File(audioFile.filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл недоступен.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    if (Platform.isAndroid) {
      bool hasPermission = false;
      
      if (await Permission.audio.isGranted) {
        hasPermission = true;
      } else {
        final status = await Permission.audio.request();
        hasPermission = status.isGranted;
      }
      
      if (!hasPermission && await Permission.storage.isGranted) {
        hasPermission = true;
      }
      
      if (!hasPermission) {
        _showPermissionWarning();
        return;
      }
    }
    
    final currentMetadata = await _audioService.getMetadata(audioFile.filePath);
    
    if (currentMetadata == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить теги')),
        );
      }
      return;
    }
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditTagsDialog(
        initialMetadata: currentMetadata,
        filePath: audioFile.filePath,
      ),
    );
    
    if (result == true) {
      await _audioService.refreshFileData(audioFile.filePath);
      await _loadAudioFiles();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Теги успешно обновлены!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
    
  } catch (e) {
    _logger.e("Error editing tags: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при сохранении тегов'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

void _showPermissionWarning() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Требуется разрешение'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning, size: 48, color: Colors.orange),
          SizedBox(height: 16),
          Text(
            'Для редактирования тегов необходимо разрешение на доступ к файлам.',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Пожалуйста, предоставьте разрешение в настройках приложения.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            openAppSettings();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: Text('Открыть настройки'),
        ),
      ],
    ),
  );
}

  Widget _buildMiniPlayer() {
    return Consumer<PlayerStateService>(
      builder: (context, playerState, child) {
        if (playerState.currentPlayingFile == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () => _openFullScreenPlayer(playerState),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
      child: Column(
            children: [
              LinearProgressIndicator(
                value: playerState.duration.inSeconds > 0 
                    ? playerState.position.inSeconds / playerState.duration.inSeconds 
                    : 0,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                minHeight: 2,
              ),
                
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openFullScreenPlayer(playerState),
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: playerState.currentAlbumArt != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.memory(
                                      playerState.currentAlbumArt!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return _buildMiniPlayerPlaceholder();
                                      },
                                    ),
                                  )
                                : _buildMiniPlayerPlaceholder(),
                          ),
                        ),
                        
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openFullScreenPlayer(playerState),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playerState.currentPlayingFile!.title ?? 
                                  playerState.currentPlayingFile!.fileName.replaceAll(
                                    RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
                                    ''
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  playerState.currentPlayingFile!.artist ?? 'Неизвестный исполнитель',
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
                        ),
                        
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                playerState.autoPlayNext ? Icons.repeat_one : Icons.repeat_one_outlined,
                                size: 18,
                              ),
                              onPressed: _toggleAutoPlay,
                              color: playerState.autoPlayNext ? Colors.green : Colors.grey.shade600,
                              padding: EdgeInsets.all(4),
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: playerState.autoPlayNext ? 'Автовоспроизведение включено' : 'Автовоспроизведение выключено',
                            ),
                            
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
                                  playerState.isPlaying ? Icons.pause : Icons.play_arrow,
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
                              onPressed: () => _openFullScreenPlayer(playerState),
                              color: Colors.grey.shade600,
                              padding: EdgeInsets.all(4),
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: 'Полноэкранный плеер',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayerPlaceholder() {
    return Center(
      child: Icon(
        Icons.music_note, 
        color: Colors.grey.shade600, 
        size: 20
      ),
    );
  }

  Future<void> _togglePlayPause() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    await playerState.togglePlayPause();
  }

  void _toggleAutoPlay() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    final newValue = !playerState.autoPlayNext;
    playerState.setAutoPlayNext(newValue);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newValue ? 'Автовоспроизведение включено' : 'Автовоспроизведение выключено'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openFullScreenPlayer(PlayerStateService playerState) {
    if (playerState.currentPlayingFile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleExampleApp(audioFile: playerState.currentPlayingFile!),
        ),
      );
    }
  }

  Future<void> _playNext() async {
    PlayerStateService? playerState;
    try {
      playerState = Provider.of<PlayerStateService>(context, listen: false);
    } catch (e) {
      _logger.e("Cannot access PlayerStateService: $e");
      return;
    }
    
    if (_audioFiles.isEmpty || playerState?.currentPlayingFile == null) return;
    
    final currentIndex = _audioFiles.indexWhere((file) => file.filePath == playerState!.currentPlayingFile!.filePath);
    if (currentIndex == -1) return;
    
    final nextIndex = (currentIndex + 1) % _audioFiles.length;
    playAudioFile(_audioFiles[nextIndex]);
  }

  Future<void> _playPrevious() async {
    PlayerStateService? playerState;
    try {
      playerState = Provider.of<PlayerStateService>(context, listen: false);
    } catch (e) {
      _logger.e("Cannot access PlayerStateService: $e");
      return;
    }
    
    if (_audioFiles.isEmpty || playerState?.currentPlayingFile == null) return;
    
    final currentIndex = _audioFiles.indexWhere((file) => file.filePath == playerState!.currentPlayingFile!.filePath);
    if (currentIndex == -1) return;
    
    final prevIndex = currentIndex == 0 ? _audioFiles.length - 1 : currentIndex - 1;
    playAudioFile(_audioFiles[prevIndex]);
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('Музыкальный плеер'),
      backgroundColor: const Color.fromARGB(255, 49, 168, 215),
      elevation: 0,
    ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : pickMultipleFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 99, 198, 47),
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                minimumSize: Size(double.infinity, 60),
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
                  : Icon(Icons.audio_file, size: 24),
              label: isLoading
                  ? Text('Загрузка...', style: TextStyle(fontSize: 20))
                  : Text('Добавить музыку', style: TextStyle(fontSize: 20)),
            ),
          ),
          
          if (_audioFiles.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Редактируйте теги через контекстное меню файла',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: !_isInitialized 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Загрузка библиотеки...'),
                      ],
                    ),
                  )
                : _audioFiles.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _audioFiles.length,
                        itemBuilder: (context, index) {
                          final audioFile = _audioFiles[index];
                          final playerState = Provider.of<PlayerStateService>(context);
                          final isCurrentPlaying = playerState.currentPlayingFile?.filePath == audioFile.filePath;
                          
                          return AudioFileItem(
                            key: ValueKey('${audioFile.filePath}-$index'),
                            audioFile: audioFile,
                            audioService: _audioService,
                            isCurrentPlaying: isCurrentPlaying,
                            isPlaying: playerState.isPlaying && isCurrentPlaying,
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
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: 20),
            Text(
              'Ваша музыкальная библиотека пуста',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'Нажмите кнопку "Добавить музыку" выше,\nчтобы начать добавлять треки в библиотеку',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    final mb = bytes / (1024 * 1024);
    return mb >= 1 
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(bytes / 1024).toStringAsFixed(0)} KB';
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

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '--:--';
    
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
              '${_formatDuration(widget.audioFile.duration)} • ${widget.audioFile.fileExtension.toUpperCase()} • ${getFileSize()}',
              style: TextStyle(
                fontSize: 11,
                color: widget.isCurrentPlaying ? Colors.green.shade400 : Colors.grey.shade500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
              icon: Icon(Icons.edit, color: Colors.blue, size: 20),
              onPressed: widget.onEdit,
              tooltip: 'Редактировать теги',
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: Icon(
                widget.isCurrentPlaying && widget.isPlaying ? Icons.pause : Icons.play_arrow, 
                color: Colors.green,
                size: 20,
              ),
              onPressed: widget.onPlay,
              tooltip: widget.isCurrentPlaying && widget.isPlaying ? 'Пауза' : 'Воспроизвести',
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: widget.onRemove,
              tooltip: 'Удалить',
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
        onTap: widget.onPlay,
      ),
    );
  }
}