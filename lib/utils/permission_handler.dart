import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class PermissionHandler {
  static Future<bool> checkAndRequestWritePermission() async {
    if (!Platform.isAndroid) return true;
    
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkVersion = androidInfo.version.sdkInt;
    
    
    if (sdkVersion >= 30) {
      return await _handleAndroid11Plus();
    } else if (sdkVersion == 29) {
      return await _handleAndroid10();
    } else {
      return await _handleAndroidLegacy();
    }
  }
  
  static Future<bool> _handleAndroid11Plus() async {
    if (await Permission.manageExternalStorage.isGranted) {
      print("MANAGE_EXTERNAL_STORAGE granted");
      return true;
    }
    
    final status = await Permission.manageExternalStorage.request();
    
    if (status.isGranted) {
      return true;
    } else {
      await openAppSettings();
      return false;
    }
  }
  
  static Future<bool> _handleAndroid10() async {
    if (await Permission.storage.isGranted) {
      return true;
    }
    
    final status = await Permission.storage.request();
    return status.isGranted;
  }
  
  static Future<bool> _handleAndroidLegacy() async {
    if (await Permission.storage.isGranted) {
      return true;
    }
    
    final status = await Permission.storage.request();
    return status.isGranted;
  }
}