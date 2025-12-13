import 'package:flutter/material.dart';
import 'package:musicplayer/audio_service.dart';
import 'package:musicplayer/singlefilepicker.dart';
import 'package:musicplayer/albums_page.dart';
import 'package:musicplayer/artists_page.dart';
import 'package:musicplayer/audio_player_service.dart';
import 'package:musicplayer/player_state_service.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AudioPlayerService().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PlayerStateService(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const MainNavigation(),
        theme: ThemeData(
          primarySwatch: Colors.green,
          useMaterial3: true,
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const Singlefilepicker(),
    const AlbumsPage(),
    const ArtistsPage(),
  ];

  final List<String> _titles = [
    'Все треки',
    'Альбомы',
    'Исполнители',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audioService = AudioService();
    final playerState = Provider.of<PlayerStateService>(context, listen: false);
    
    audioService.addFileUpdateListener((filePath) {
      if (playerState.currentPlayingFile?.filePath == filePath) {
        playerState.refreshCurrentFile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        backgroundColor: const Color.fromARGB(255, 49, 168, 215),
        elevation: 0,
      ),
      body: Consumer<PlayerStateService>(
        builder: (context, playerState, child) {
          return _pages[_currentIndex];
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          
          final playerState = Provider.of<PlayerStateService>(context, listen: false);
          playerState.syncWithAudioService();
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: 'Треки',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.album),
            label: 'Альбомы',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Исполнители',
          ),
        ],
      ),
    );
  }
}
