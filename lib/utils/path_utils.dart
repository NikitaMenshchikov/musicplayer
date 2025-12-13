import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class PathUtils {
  static bool isTemporaryPath(String path) {
    if (path.isEmpty) return false;
    
    final tempPatterns = [
      '/cache/file_picker/',
      '/cache/',
      '/temp/',
      '/tmp/',
      'com.example.musicplayer/cache/', 
    ];
    
    return tempPatterns.any((pattern) => path.contains(pattern));
  }
  
  static Future<String?> findOriginalPath(String tempPath, String fileName) async {
    if (!isTemporaryPath(tempPath)) {
      return tempPath; 
    }
    
    if (Platform.isAndroid) {
      final musicDirs = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0',
      ];
      
      for (final dir in musicDirs) {
        final possiblePath = p.join(dir, fileName);
        final file = File(possiblePath);
        if (await file.exists()) {
          return possiblePath;
        }
      }
    }
    
    return null; 
  }
  
  static Future<bool> hasStorageAccess() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      if (deviceInfo.version.sdkInt >= 33) {
        return await Permission.audio.status.isGranted;
      } else {
        return await Permission.storage.status.isGranted;
      }
    }
    return true;
  }
}