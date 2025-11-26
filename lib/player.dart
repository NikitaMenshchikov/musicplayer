import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:audiotags/audiotags.dart';

class SimpleExampleApp extends StatefulWidget {
  final PlatformFile file;
  const SimpleExampleApp({required this.file, super.key});

  @override
  SimpleExampleAppState createState() => SimpleExampleAppState();
}

class SimpleExampleAppState extends State<SimpleExampleApp> {
  late AudioPlayer player;
  Tag? metadata;
  bool isLoadingMetadata = true;

  @override
  void initState() {
    super.initState();
    player = AudioPlayer();
    player.setReleaseMode(ReleaseMode.stop);
    
    _loadMetadata();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _playFile();
    });
  }

  Future<void> _loadMetadata() async {
    if (widget.file.path != null) {
      try {
        final tag = await AudioTags.read(widget.file.path!);
        setState(() {
          metadata = tag;
          isLoadingMetadata = false;
        });
      } catch (e) {
        print("Error loading metadata in player: $e");
        setState(() {
          isLoadingMetadata = false;
        });
      }
    }
  }

  Future<void> _playFile() async {
    if (widget.file.path != null) {
      try {
        await player.setSource(DeviceFileSource(widget.file.path!));
        await player.resume();
      } catch (e) {
        print("Ошибка воспроизведения: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения файла')),
        );
      }
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String getTitle() {
    if (isLoadingMetadata) return widget.file.name;
    return metadata?.title ??  widget.file.name.replaceAll(RegExp(r'\.(mp3|wav|aac|m4a|ogg|flac)$', caseSensitive: false), '');
  }

  String getArtist() {
    if (isLoadingMetadata) return 'Загрузка...';
    return metadata?.trackArtist ?? 'Неизвестный исполнитель';
  }

  String getAlbum() {
    if (isLoadingMetadata) return '';
    return metadata?.album ?? 'Неизвестный альбом';
  }

  int? getYear() {
    return metadata?.year;
  }

  String? getGenre() {
    return metadata?.genre;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLoadingMetadata ? 'Загрузка...' : 'Сейчас играет'),
        backgroundColor: Color.fromARGB(255, 47, 225, 121),
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
                    CircularProgressIndicator(),
                  PlayerWidget(player: player),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataCard() {
    final title = getTitle();
    final artist = getArtist();
    final album = getAlbum();

    return Card(
      margin: EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.album,
                size: 60,
                color: Colors.blue.shade600,
              ),
            ),
            SizedBox(height: 16),
            
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8),
            
            Text(
              artist,
              style: TextStyle(
                fontSize: 16,
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
                fontSize: 14,
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
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],

            if (getGenre() != null) ...[
              SizedBox(height: 2),
              Text(
                'Жанр: ${getGenre()}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlayerWidget extends StatefulWidget {
  final AudioPlayer player;
  const PlayerWidget({required this.player, super.key});
  
  @override
  State<StatefulWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  PlayerState? _playerState;
  Duration? _duration;
  Duration? _position;

  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerCompleteSubscription;
  StreamSubscription? _playerStateChangeSubscription;

  bool get _isPlaying => _playerState == PlayerState.playing;
  bool get _isPaused => _playerState == PlayerState.paused;

  String get _durationText => _duration?.toString().split('.').first ?? '';
  String get _positionText => _position?.toString().split('.').first ?? '';

  AudioPlayer get player => widget.player;

  @override
  void initState() {
    super.initState();
    _playerState = player.state;
    player.getDuration().then((value) => setState(() => _duration = value));
    player.getCurrentPosition().then((value) => setState(() => _position = value));
    _initStreams();
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _playerStateChangeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).primaryColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('play_button'),
              onPressed: _isPlaying ? null : _play,
              iconSize: 48.0,
              icon: const Icon(Icons.play_arrow),
              color: color,
            ),
            IconButton(
              key: const Key('pause_button'),
              onPressed: _isPlaying ? _pause : null,
              iconSize: 48.0,
              icon: const Icon(Icons.pause),
              color: color,
            ),
            IconButton(
              key: const Key('stop_button'),
              onPressed: _isPlaying || _isPaused ? _stop : null,
              iconSize: 48.0,
              icon: const Icon(Icons.stop),
              color: color,
            ),
          ],
        ),
        Slider(
          onChanged: (value) {
            final duration = _duration;
            if (duration == null) return;
            final position = value * duration.inMilliseconds;
            player.seek(Duration(milliseconds: position.round()));
          },
          value: (_position != null && _duration != null && _position!.inMilliseconds > 0 && _position!.inMilliseconds < _duration!.inMilliseconds)
              ? _position!.inMilliseconds / _duration!.inMilliseconds
              : 0.0,
        ),
        Text(
          _position != null ? '$_positionText / $_durationText' : _duration != null ? _durationText : '',
          style: const TextStyle(fontSize: 16.0),
        ),
      ],
    );
  }

  void _initStreams() {
    _durationSubscription = player.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });
    _positionSubscription = player.onPositionChanged.listen((p) => setState(() => _position = p));
    _playerCompleteSubscription = player.onPlayerComplete.listen((event) {
      setState(() {
        _playerState = PlayerState.stopped;
        _position = Duration.zero;
      });
    });
    _playerStateChangeSubscription = player.onPlayerStateChanged.listen((state) {
      setState(() => _playerState = state);
    });
  }

  Future<void> _play() async {
    await player.resume();
    setState(() => _playerState = PlayerState.playing);
  }

  Future<void> _pause() async {
    await player.pause();
    setState(() => _playerState = PlayerState.paused);
  }

  Future<void> _stop() async {
    await player.stop();
    setState(() {
      _playerState = PlayerState.stopped;
      _position = Duration.zero;
    });
  }
}