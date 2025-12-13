import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/player_state_service.dart';
import 'package:musicplayer/player.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  final AudioService _audioService = AudioService();
  List<AudioFileModel> _audioFiles = [];
  List<Album> _albums = [];
  bool isLoading = false;
  bool _isInitialized = false;
  String _searchQuery = '';
  bool _isDisposed = false; 

@override
void initState() {
  super.initState();
  _loadData();
  _audioService.addFileUpdateListener(_onFileUpdated);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _setupCompletionListener();
  });
}
    @override
  void dispose() {
    _isDisposed = true; 
    _audioService.removeFileUpdateListener(_onFileUpdated);
    super.dispose();
  }

void _setupCompletionListener() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    playerState.addCompletionListener(_onTrackCompletion);
  });
}

void _onTrackCompletion() {
  if (mounted && _audioFiles.isNotEmpty) {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (playerState.autoPlayNext) {
      _playNextTrack();
    }
  }
}

  void _onFileUpdated(String filePath) {
    if (!_isDisposed && mounted) { 
      _loadData();
    }
  }


Future<void> _loadData() async {
  if (!mounted || _isDisposed) return;
  
  setState(() {
    isLoading = true;
  });

  try {
    _audioFiles = await _audioService.getAudioFilesWithRefresh();
    if (!mounted || _isDisposed) return;
    
    _albums = _groupTracksByAlbum(_audioFiles);
    print("Loaded ${_albums.length} albums with refreshed metadata");
    
  } catch (e) {
    print("Error loading data: $e");
    _audioFiles = await _audioService.getAudioFiles();
    if (!mounted || _isDisposed) return;
    _albums = _groupTracksByAlbum(_audioFiles);
  } finally {
    if (!mounted || _isDisposed) return;
    setState(() {
      isLoading = false;
      _isInitialized = true;
    });
  }
}

  List<Album> _groupTracksByAlbum(List<AudioFileModel> files) {
    final albumMap = <String, Album>{};
    
    for (final file in files) {
      final artist = file.artist ?? 'Неизвестный исполнитель';
      final albumName = file.album ?? 'Без альбома';
      
      final albumKey = '$artist|$albumName';
      
      if (!albumMap.containsKey(albumKey)) {
        albumMap[albumKey] = Album(
          name: albumName,
          artist: artist,
          tracks: [],
          coverArt: null,
        );
      }
      
      albumMap[albumKey]!.tracks.add(file);
    }

    for (final album in albumMap.values) {
      album.tracks.sort((a, b) {
        final trackA = a.trackNumber ?? 0;
        final trackB = b.trackNumber ?? 0;
        return trackA.compareTo(trackB);
      });
    }

    final albums = albumMap.values.toList();
    _loadAlbumCovers(albums);
    
    return albums;
  }

  Future<void> _loadAlbumCovers(List<Album> albums) async {
    for (final album in albums) {
      if (album.tracks.isNotEmpty) {
        try {
          final cover = await _audioService.getCover(album.tracks.first.filePath);
          if (mounted) {
            setState(() {
              album.coverArt = cover;
            });
          }
        } catch (e) {
          print("Error loading cover for album ${album.name}: $e");
        }
      }
    }
  }

void playTrack(AudioFileModel track) {
  final playerState = Provider.of<PlayerStateService>(context, listen: false);
  playerState.playAudioFileWithForceUpdate(track); 
}

  void playAlbum(Album album) {
    if (album.tracks.isEmpty) return;
    
    playTrack(album.tracks.first);
  }

  Future<void> _playNextTrack() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_audioFiles.isEmpty || playerState.currentPlayingFile == null) return;

    final currentAlbum = _findAlbumForTrack(playerState.currentPlayingFile!);
    if (currentAlbum != null) {
      final currentIndex = currentAlbum.tracks.indexWhere(
        (track) => track.filePath == playerState.currentPlayingFile!.filePath
      );
      
      if (currentIndex != -1 && currentIndex < currentAlbum.tracks.length - 1) {
        playTrack(currentAlbum.tracks[currentIndex + 1]);
        return;
      }
    }

    _playNextAlbum();
  }

  Future<void> _playPreviousTrack() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_audioFiles.isEmpty || playerState.currentPlayingFile == null) return;

    final currentAlbum = _findAlbumForTrack(playerState.currentPlayingFile!);
    if (currentAlbum != null) {
      final currentIndex = currentAlbum.tracks.indexWhere(
        (track) => track.filePath == playerState.currentPlayingFile!.filePath
      );
      
      if (currentIndex != -1 && currentIndex > 0) {
        playTrack(currentAlbum.tracks[currentIndex - 1]);
        return;
      } else if (currentIndex == 0) {
        _playPreviousAlbum();
      }
    }
  }

  void _playPreviousAlbum() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_albums.isEmpty || playerState.currentPlayingFile == null) return;

    final currentAlbum = _findAlbumForTrack(playerState.currentPlayingFile!);
    if (currentAlbum != null) {
      final currentIndex = _albums.indexWhere(
        (album) => album.name == currentAlbum.name && album.artist == currentAlbum.artist
      );
      
      if (currentIndex != -1 && currentIndex > 0) {
        final prevAlbum = _albums[currentIndex - 1];
        if (prevAlbum.tracks.isNotEmpty) {
          playTrack(prevAlbum.tracks.last);
        }
      } else if (currentIndex == 0) {
        if (_albums.last.tracks.isNotEmpty) {
          playTrack(_albums.last.tracks.last);
        }
      }
    }
  }

  void _playNextAlbum() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_albums.isEmpty || playerState.currentPlayingFile == null) return;

    final currentAlbum = _findAlbumForTrack(playerState.currentPlayingFile!);
    if (currentAlbum != null) {
      final currentIndex = _albums.indexWhere(
        (album) => album.name == currentAlbum.name && album.artist == currentAlbum.artist
      );
      
      if (currentIndex != -1 && currentIndex < _albums.length - 1) {
        final nextAlbum = _albums[currentIndex + 1];
        if (nextAlbum.tracks.isNotEmpty) {
          playTrack(nextAlbum.tracks.first);
        }
      } else {
        if (_albums.first.tracks.isNotEmpty) {
          playTrack(_albums.first.tracks.first);
        }
      }
    }
  }

  Album? _findAlbumForTrack(AudioFileModel track) {
    final artist = track.artist ?? 'Неизвестный исполнитель';
    final albumName = track.album ?? 'Без альбома';
    
    return _albums.firstWhere(
      (album) => album.name == albumName && album.artist == artist,
      orElse: () => Album(name: '', artist: '', tracks: []),
    );
  }

  List<Album> get _filteredAlbums {
    if (_searchQuery.isEmpty) return _albums;
    
    return _albums.where((album) {
      return album.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             album.artist.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

Widget _buildMiniPlayer() {
  return Consumer<PlayerStateService>(
    builder: (context, playerState, child) {
      
      if (playerState.currentPlayingFile == null) {
        return const SizedBox.shrink();
      }

      return GestureDetector(
        onTap: () => _openFullScreenPlayer(),
        child: Container(
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
                        onTap: () => _openFullScreenPlayer(),
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
                                  ),
                                )
                              : Icon(Icons.music_note, color: Colors.grey.shade600, size: 20),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openFullScreenPlayer(),
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
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              SizedBox(height: 2),
                              Text(
                                playerState.currentPlayingFile!.artist ?? 'Неизвестный исполнитель',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                            icon: Icon(Icons.skip_previous, size: 20),
                            onPressed: _playPreviousTrack,
                            color: Colors.blue.shade600,
                            padding: EdgeInsets.all(4),
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
                            onPressed: _playNextTrack,
                            color: Colors.blue.shade600,
                            padding: EdgeInsets.all(4),
                          ),
                          SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.fullscreen, size: 18),
                            onPressed: _openFullScreenPlayer,
                            color: Colors.grey.shade600,
                            padding: EdgeInsets.all(4),
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

  Future<void> _togglePlayPause() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    await playerState.togglePlayPause();
  }

  void _openFullScreenPlayer() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (playerState.currentPlayingFile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleExampleApp(audioFile: playerState.currentPlayingFile!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск альбомов...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: !_isInitialized
                ? Center(child: CircularProgressIndicator())
                : _filteredAlbums.isEmpty
                    ? _buildEmptyState()
                    : _buildAlbumsGrid(),
          ),
          _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    final playerState = Provider.of<PlayerStateService>(context);
    
    return GridView.builder(
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: _filteredAlbums.length,
      itemBuilder: (context, index) {
        final album = _filteredAlbums[index];
        return _buildAlbumCard(album, playerState);
      },
    );
  }

  Widget _buildAlbumCard(Album album, PlayerStateService playerState) {
    final isCurrentAlbum = playerState.currentPlayingFile != null &&
        album.tracks.any((track) => track.filePath == playerState.currentPlayingFile!.filePath);

    return Card(
      elevation: 4,
      color: isCurrentAlbum ? Colors.green.shade50 : null,
      child: InkWell(
        onTap: () => _showAlbumDetails(album),
        onLongPress: () => playAlbum(album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                  border: isCurrentAlbum ? Border.all(color: Colors.green, width: 2) : null,
                ),
                child: album.coverArt != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                        child: Image.memory(
                          album.coverArt!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.album,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isCurrentAlbum ? Colors.green.shade800 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    album.artist,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrentAlbum ? Colors.green.shade600 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${album.tracks.length} трек${_getTrackEnding(album.tracks.length)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isCurrentAlbum ? Colors.green.shade500 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTrackEnding(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) return 'а';
    return 'ов';
  }

  void _showAlbumDetails(Album album) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AlbumDetailsSheet(
        album: album,
        onTrackSelected: playTrack,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.album, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Нет альбомов' : 'Альбомы не найдены',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          if (_searchQuery.isEmpty) ...[
            SizedBox(height: 8),
            Text(
              'Добавьте музыку чтобы увидеть альбомы',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

class Album {
  final String name;
  final String artist;
  final List<AudioFileModel> tracks;
  Uint8List? coverArt;

  Album({
    required this.name,
    required this.artist,
    required this.tracks,
    this.coverArt,
  });
}

class AlbumDetailsSheet extends StatelessWidget {
  final Album album;
  final Function(AudioFileModel) onTrackSelected;

  const AlbumDetailsSheet({
    required this.album,
    required this.onTrackSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final playerState = Provider.of<PlayerStateService>(context);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: album.coverArt != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          album.coverArt!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.album,
                          size: 32,
                          color: Colors.grey.shade400,
                        ),
                      ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      album.artist,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${album.tracks.length} трек${_getTrackEnding(album.tracks.length)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: album.tracks.length,
              itemBuilder: (context, index) {
                final track = album.tracks[index];
                final isCurrentPlaying = playerState.currentPlayingFile?.filePath == track.filePath;
                
                return ListTile(
                  leading: Icon(
                    Icons.music_note,
                    color: isCurrentPlaying ? Colors.green : null,
                  ),
                  title: Text(
                    track.title ?? 
                    track.fileName.replaceAll(
                      RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), 
                      ''
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrentPlaying ? Colors.green : null,
                      fontWeight: isCurrentPlaying ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: Text(
                    '${track.trackNumber != null ? '${track.trackNumber}. ' : ''}${_formatDuration(track.duration)}',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: isCurrentPlaying && playerState.isPlaying
                      ? Icon(Icons.equalizer, color: Colors.green)
                      : null,
                  onTap: () {
                    onTrackSelected(track);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getTrackEnding(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) return 'а';
    return 'ов';
  }

String _formatDuration(int milliseconds) {
  if (milliseconds <= 0) return '00:00';
  
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
}