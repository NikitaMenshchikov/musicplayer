class AudioFileModel {
  final int? id;
  final String filePath;
  final String fileName;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int fileSize;
  final String fileExtension;
  final int duration; 
  final DateTime dateAdded;

  AudioFileModel({
    this.id,
    required this.filePath,
    required this.fileName,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.trackNumber,
    required this.fileSize,
    required this.fileExtension,
    required this.duration,
    required this.dateAdded,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'track_number': trackNumber,
      'file_size': fileSize,
      'file_extension': fileExtension,
      'duration': duration,
      'date_added': dateAdded.millisecondsSinceEpoch,
    };
  }

  factory AudioFileModel.fromMap(Map<String, dynamic> map) {
    return AudioFileModel(
      id: map['id'],
      filePath: map['file_path'],
      fileName: map['file_name'],
      title: map['title'],
      artist: map['artist'],
      album: map['album'],
      genre: map['genre'],
      year: map['year'],
      trackNumber: map['track_number'],
      fileSize: map['file_size'],
      fileExtension: map['file_extension'],
      duration: map['duration'],
      dateAdded: DateTime.fromMillisecondsSinceEpoch(map['date_added']),
    );
  }
}