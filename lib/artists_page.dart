import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:musicplayer/models/audio_file_model.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/player_state_service.dart';
import 'package:musicplayer/player.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  final AudioService _audioService = AudioService();
  List<AudioFileModel> _audioFiles = [];
  List<Artist> _artists = [];
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
    
    _artists = _groupTracksByArtist(_audioFiles); 
    print("Loaded ${_artists.length} albums with refreshed metadata");
    
  } catch (e) {
    print("Error loading data: $e");
    _audioFiles = await _audioService.getAudioFiles();
    if (!mounted || _isDisposed) return;
    _artists = _groupTracksByArtist(_audioFiles);
  } finally {
    if (!mounted || _isDisposed) return;
    setState(() {
      isLoading = false;
      _isInitialized = true;
    });
  }
}


  List<Artist> _groupTracksByArtist(List<AudioFileModel> files) {
    final artistMap = <String, Artist>{};
    
    for (final file in files) {
      final artistName = file.artist ?? 'Неизвестный исполнитель';
      
      if (!artistMap.containsKey(artistName)) {
        artistMap[artistName] = Artist(
          name: artistName,
          albums: {},
        );
      }
      
      final albumName = file.album ?? 'Без альбома';
      if (!artistMap[artistName]!.albums.containsKey(albumName)) {
        artistMap[artistName]!.albums[albumName] = [];
      }
      
      artistMap[artistName]!.albums[albumName]!.add(file);
    }
    for (final artist in artistMap.values) {
      for (final album in artist.albums.values) {
        album.sort((a, b) {
          final trackA = a.trackNumber ?? 0;
          final trackB = b.trackNumber ?? 0;
          return trackA.compareTo(trackB);
        });
      }
    }

    return artistMap.values.toList();
  }

  List<Artist> get _filteredArtists {
    if (_searchQuery.isEmpty) return _artists;
    
    return _artists.where((artist) {
      return artist.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

void playTrack(AudioFileModel track) {
  final playerState = Provider.of<PlayerStateService>(context, listen: false);
  playerState.playAudioFileWithForceUpdate(track); 
}

  Future<void> _playNextTrack() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_audioFiles.isEmpty || playerState.currentPlayingFile == null) return;

    final currentArtist = _findArtistForTrack(playerState.currentPlayingFile!);
    if (currentArtist != null) {
      final currentAlbumName = playerState.currentPlayingFile!.album ?? 'Без альбома';
      final currentAlbum = currentArtist.albums[currentAlbumName];
      
      if (currentAlbum != null) {
        final currentIndex = currentAlbum.indexWhere(
          (track) => track.filePath == playerState.currentPlayingFile!.filePath
        );
        
        if (currentIndex != -1 && currentIndex < currentAlbum.length - 1) {
          playTrack(currentAlbum[currentIndex + 1]);
          return;
        }
        
        _playNextAlbum(currentArtist, currentAlbumName);
        return;
      }
    }

    _playNextInLibrary();
  }

  Future<void> _playPreviousTrack() async {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    if (_audioFiles.isEmpty || playerState.currentPlayingFile == null) return;

    final currentArtist = _findArtistForTrack(playerState.currentPlayingFile!);
    if (currentArtist != null) {
      final currentAlbumName = playerState.currentPlayingFile!.album ?? 'Без альбома';
      final currentAlbum = currentArtist.albums[currentAlbumName];
      
      if (currentAlbum != null) {
        final currentIndex = currentAlbum.indexWhere(
          (track) => track.filePath == playerState.currentPlayingFile!.filePath
        );
        
        if (currentIndex != -1 && currentIndex > 0) {
          playTrack(currentAlbum[currentIndex - 1]);
          return;
        } else if (currentIndex == 0) {
          _playPreviousAlbum(currentArtist, currentAlbumName);
          return;
        }
      }
    }

    _playPreviousInLibrary();
  }

  void _playNextAlbum(Artist artist, String currentAlbumName) {
    final albumNames = artist.albums.keys.toList();
    final currentIndex = albumNames.indexOf(currentAlbumName);
    
    if (currentIndex != -1 && currentIndex < albumNames.length - 1) {
      final nextAlbumName = albumNames[currentIndex + 1];
      final nextAlbum = artist.albums[nextAlbumName];
      if (nextAlbum != null && nextAlbum.isNotEmpty) {
        playTrack(nextAlbum.first);
      }
    } else {
      _playNextArtist(artist);
    }
  }

  void _playPreviousAlbum(Artist artist, String currentAlbumName) {
    final albumNames = artist.albums.keys.toList();
    final currentIndex = albumNames.indexOf(currentAlbumName);
    
    if (currentIndex != -1 && currentIndex > 0) {
      final prevAlbumName = albumNames[currentIndex - 1];
      final prevAlbum = artist.albums[prevAlbumName];
      if (prevAlbum != null && prevAlbum.isNotEmpty) {
        playTrack(prevAlbum.last); 
      }
    } else if (currentIndex == 0) {
      _playPreviousArtist(artist);
    }
  }

  void _playNextArtist(Artist currentArtist) {
    final currentIndex = _artists.indexWhere((a) => a.name == currentArtist.name);
    if (currentIndex != -1 && currentIndex < _artists.length - 1) {
      final nextArtist = _artists[currentIndex + 1];
      final firstAlbum = nextArtist.albums.values.firstWhere(
        (album) => album.isNotEmpty,
        orElse: () => [],
      );
      if (firstAlbum.isNotEmpty) {
        playTrack(firstAlbum.first);
      }
    } else {
      final firstArtist = _artists.first;
      final firstAlbum = firstArtist.albums.values.firstWhere(
        (album) => album.isNotEmpty,
        orElse: () => [],
      );
      if (firstAlbum.isNotEmpty) {
        playTrack(firstAlbum.first);
      }
    }
  }

  void _playPreviousArtist(Artist currentArtist) {
    final currentIndex = _artists.indexWhere((a) => a.name == currentArtist.name);
    if (currentIndex != -1 && currentIndex > 0) {
      final prevArtist = _artists[currentIndex - 1];
      final lastAlbum = prevArtist.albums.values.lastWhere(
        (album) => album.isNotEmpty,
        orElse: () => [],
      );
      if (lastAlbum.isNotEmpty) {
        playTrack(lastAlbum.last);
      }
    } else if (currentIndex == 0) {
      final lastArtist = _artists.last;
      final lastAlbum = lastArtist.albums.values.lastWhere(
        (album) => album.isNotEmpty,
        orElse: () => [],
      );
      if (lastAlbum.isNotEmpty) {
        playTrack(lastAlbum.last);
      }
    }
  }

  void _playNextInLibrary() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    final currentIndex = _audioFiles.indexWhere(
      (track) => track.filePath == playerState.currentPlayingFile!.filePath
    );
    
    if (currentIndex != -1 && currentIndex < _audioFiles.length - 1) {
      playTrack(_audioFiles[currentIndex + 1]);
    } else if (_audioFiles.isNotEmpty) {
      playTrack(_audioFiles.first);
    }
  }

  void _playPreviousInLibrary() {
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    final currentIndex = _audioFiles.indexWhere(
      (track) => track.filePath == playerState.currentPlayingFile!.filePath
    );
    
    if (currentIndex != -1 && currentIndex > 0) {
      playTrack(_audioFiles[currentIndex - 1]);
    } else if (_audioFiles.isNotEmpty) {
      playTrack(_audioFiles.last);
    }
  }

  Artist? _findArtistForTrack(AudioFileModel track) {
    final artistName = track.artist ?? 'Неизвестный исполнитель';
    return _artists.firstWhere(
      (artist) => artist.name == artistName,
      orElse: () => Artist(name: '', albums: {}),
    );
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
                                  child: Image.memory(playerState.currentAlbumArt!, fit: BoxFit.cover),
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
                                playerState.currentPlayingFile!.fileName.replaceAll(RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), ''),
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
                            decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            child: IconButton(
                              icon: Icon(
                                playerState.isPlaying ? Icons.pause : Icons.play_arrow, 
                                size: 16, 
                                color: Colors.white
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
                hintText: 'Поиск исполнителей...',
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
                : _filteredArtists.isEmpty
                    ? _buildEmptyState()
                    : _buildArtistsList(),
          ),
          _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildArtistsList() {
    final playerState = Provider.of<PlayerStateService>(context);
    
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredArtists.length,
      itemBuilder: (context, index) {
        final artist = _filteredArtists[index];
        return _buildArtistCard(artist, playerState);
      },
    );
  }

  Widget _buildArtistCard(Artist artist, PlayerStateService playerState) {
    final albumCount = artist.albums.length;
    final trackCount = artist.albums.values.fold<int>(0, (sum, album) => sum + album.length);
    final hasCurrentTrack = playerState.currentPlayingFile != null &&
        artist.albums.values.any((album) => 
          album.any((track) => track.filePath == playerState.currentPlayingFile!.filePath));

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: hasCurrentTrack ? Colors.green.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasCurrentTrack ? Colors.green.shade100 : Colors.grey.shade200,
          child: Icon(
            Icons.person, 
            color: hasCurrentTrack ? Colors.green : Colors.grey.shade600
          ),
        ),
        title: Text(
          artist.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: hasCurrentTrack ? Colors.green.shade800 : null,
          ),
        ),
        subtitle: Text(
          '$albumCount альбомов • $trackCount треков',
          style: TextStyle(
            color: hasCurrentTrack ? Colors.green.shade600 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasCurrentTrack && playerState.isPlaying)
              Icon(Icons.equalizer, color: Colors.green, size: 16),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () => _showArtistDetails(artist),
      ),
    );
  }

  void _showArtistDetails(Artist artist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ArtistDetailsSheet(
        artist: artist,
        onTrackSelected: playTrack,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Нет исполнителей' : 'Исполнители не найдены',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          if (_searchQuery.isEmpty) ...[
            SizedBox(height: 8),
            Text(
              'Добавьте музыку чтобы увидеть исполнителей',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

class Artist {
  final String name;
  final Map<String, List<AudioFileModel>> albums;

  Artist({
    required this.name,
    required this.albums,
  });
}

class ArtistDetailsSheet extends StatelessWidget {
  final Artist artist;
  final Function(AudioFileModel) onTrackSelected;

  const ArtistDetailsSheet({
    required this.artist,
    required this.onTrackSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final playerState = Provider.of<PlayerStateService>(context);
    final albumNames = artist.albums.keys.toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.person, size: 40, color: Colors.grey.shade600),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${artist.albums.length} альбомов • ${_getTotalTracks()} треков',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: albumNames.length,
              itemBuilder: (context, index) {
                final albumName = albumNames[index];
                final tracks = artist.albums[albumName]!;
                return _buildAlbumItem(context, albumName, tracks, playerState); 
              },
            ),
          ),
        ],
      ),
    );
  }

Widget _buildAlbumItem(BuildContext context, String albumName, List<AudioFileModel> tracks, PlayerStateService playerState) {
  final hasCurrentTrack = tracks.any((track) => 
      playerState.currentPlayingFile?.filePath == track.filePath);

  return Card(
    margin: EdgeInsets.only(bottom: 8),
    color: hasCurrentTrack ? Colors.green.shade50 : null,
    child: ListTile(
      leading: Icon(
        Icons.album, 
        size: 40, 
        color: hasCurrentTrack ? Colors.green : Colors.grey.shade400
      ),
      title: Text(
        albumName,
        style: TextStyle(
          color: hasCurrentTrack ? Colors.green.shade800 : null,
        ),
      ),
      subtitle: Text(
        '${tracks.length} трек${_getTrackEnding(tracks.length)}',
        style: TextStyle(
          color: hasCurrentTrack ? Colors.green.shade600 : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasCurrentTrack && playerState.isPlaying)
            Icon(Icons.equalizer, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios, size: 16),
        ],
      ),
      onTap: () => _showAlbumTracks(context, albumName, tracks, playerState), 
    ),
  );
}

void _showAlbumTracks(BuildContext context, String albumName, List<AudioFileModel> tracks, PlayerStateService playerState) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            '$albumName - ${artist.name}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isCurrentPlaying = playerState.currentPlayingFile?.filePath == track.filePath;
                
                return ListTile(
                  leading: Icon(
                    Icons.music_note,
                    color: isCurrentPlaying ? Colors.green : null,
                  ),
                  title: Text(
                    track.title ?? 
                    track.fileName.replaceAll(RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), ''),
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
    ),
  );
}

  int _getTotalTracks() {
    return artist.albums.values.fold<int>(0, (sum, album) => sum + album.length);
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