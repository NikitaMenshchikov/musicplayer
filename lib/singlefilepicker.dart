import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/player.dart';
import 'package:audiotags/audiotags.dart';

class Singlefilepicker extends StatefulWidget {
  const Singlefilepicker({super.key});

  @override
  State<Singlefilepicker> createState() => _SinglefilepickerState();
}

class _SinglefilepickerState extends State<Singlefilepicker> {
  List<PlatformFile> audioFiles = [];
  bool isLoading = false;

  Future<void> pickMultipleFiles() async {
    setState(() {
      isLoading = true;
    });

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );

    if (result != null) {
      List<PlatformFile> newFiles = result.files;
      
      newFiles = newFiles.where((file) {
        final extension = file.extension?.toLowerCase();
        return extension == 'mp3' || 
               extension == 'm4a' ||
               extension == 'flac';
      }).toList();

      setState(() {
        audioFiles.addAll(newFiles);
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  void playAudioFile(PlatformFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleExampleApp(file: file),
      ),
    );
  }

  void removeFile(int index) {
    setState(() {
      audioFiles.removeAt(index);
    });
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
            child: audioFiles.isEmpty
                ? Center(
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
                          'Нажмите кнопку выше, чтобы добавить музыку',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: audioFiles.length,
                    itemBuilder: (context, index) {
                      return AudioFileItem(
                        file: audioFiles[index],
                        onPlay: () => playAudioFile(audioFiles[index]),
                        onRemove: () => removeFile(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AudioFileItem extends StatefulWidget {
  final PlatformFile file;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  const AudioFileItem({
    required this.file,
    required this.onPlay,
    required this.onRemove,
    super.key,
  });

  @override
  State<AudioFileItem> createState() => _AudioFileItemState();
}

class _AudioFileItemState extends State<AudioFileItem> {
  Tag? metadata;
  bool isLoadingMetadata = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    if (widget.file.path != null) {
      try {
        final tag = await AudioTags.read(widget.file.path!,
        );
        setState(() {
          metadata = tag;
          isLoadingMetadata = false;
        });
      } catch (e) {
        print("Error loading metadata with audiotags: $e");
        setState(() {
          isLoadingMetadata = false;
        });
      }
    } else {
      setState(() {
        isLoadingMetadata = false;
      });
    }
  }

  String getFileSize() {
    final bytes = widget.file.size;
    final kb = bytes / 1024;
    final mb = kb / 1024;
    return mb >= 1 
        ? '${mb.toStringAsFixed(2)} MB'
        : '${kb.toStringAsFixed(2)} KB';
  }

  String getTitle() {
    if (isLoadingMetadata) return widget.file.name;
    return metadata?.title ??  widget.file.name.replaceAll(RegExp(r'\.(mp3|m4a|flac)$', caseSensitive: false), '');
  }

  String getArtist() {
    if (isLoadingMetadata) return 'Загрузка...';
    return metadata?.trackArtist ?? 'Неизвестный исполнитель';
  }

  String getAlbum() {
    if (isLoadingMetadata) return '';
    return metadata?.album ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.audiotrack,
            color: Colors.blue.shade600,
            size: 30,
          ),
        ),
        title: Text(
          getTitle(),
          style: TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isLoadingMetadata) ...[
              Text(
                getArtist(),
                overflow: TextOverflow.ellipsis,
              ),
              if (getAlbum().isNotEmpty)
                Text(
                  'Альбом: ${getAlbum()}',
                  overflow: TextOverflow.ellipsis,
                ),
            ],
            Text(
              '${widget.file.extension?.toUpperCase()} • ${getFileSize()}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.play_arrow, color: Colors.green),
              onPressed: widget.onPlay,
              tooltip: 'Воспроизвести',
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