import 'package:file_picker/file_picker.dart';

class AudioFile {
  final PlatformFile platformFile;
  final String originalPath;
  
  AudioFile({
    required this.platformFile,
    required this.originalPath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioFile &&
          runtimeType == other.runtimeType &&
          originalPath == other.originalPath;

  @override
  int get hashCode => originalPath.hashCode;
}