import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audiotags/audiotags.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:url_launcher/url_launcher.dart'; 


class EditTagsDialog extends StatefulWidget {
  final Tag? initialMetadata;
  final String filePath;

  const EditTagsDialog({
    Key? key,
    required this.initialMetadata,
    required this.filePath,
  }) : super(key: key);

  @override
  _EditTagsDialogState createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<EditTagsDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _genreController;
  late TextEditingController _yearController;
  late TextEditingController _trackNumberController;

  bool _isSaving = false;
  final _formKey = GlobalKey<FormState>();
  Uint8List? _selectedCover;
  bool _hasCoverChanges = false;

  @override
  void initState() {
    super.initState();
    
    String? year = widget.initialMetadata?.year?.toString();
    if (year != null) {
      final yearInt = int.tryParse(year);
      if (yearInt == null || yearInt <= 0) {
        year = null;
      }
    }

    _titleController = TextEditingController(text: widget.initialMetadata?.title ?? '');
    _artistController = TextEditingController(text: widget.initialMetadata?.trackArtist ?? '');
    _albumController = TextEditingController(text: widget.initialMetadata?.album ?? '');
    _genreController = TextEditingController(text: widget.initialMetadata?.genre ?? '');
    _yearController = TextEditingController(text: year ?? '');
    _trackNumberController = TextEditingController(text: widget.initialMetadata?.trackNumber?.toString() ?? '');
    
    _initCurrentCover();
  }

  Future<bool> _checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      
      if (androidInfo.version.sdkInt >= 30) {
        
        if (await Permission.manageExternalStorage.isGranted) {
          return true;
        }
        
        final status = await Permission.manageExternalStorage.request();
        
        if (status.isGranted) {
          return true;
        }
        
        if (mounted) {
          _showManageExternalStorageDialog();
        }
        
        return false;
      } else {
        if (await Permission.storage.isGranted) {
          return true;
        }
        
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } catch (e) {
      print("Error checking permissions: $e");
      return false;
    }
  }

Future<void> _openManageFilesSettings() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        
        if (androidInfo.version.sdkInt >= 30) {
          final packageName = 'com.yourdomain.musicplayer'; 
          
          final uri = Uri.parse('package:$packageName');
          
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
            print("Error launching settings: $e");
            await openAppSettings();
          }
        } else {
          await openAppSettings();
        }
      } else {
        await openAppSettings();
      }
    } catch (e) {
      print("Error opening settings: $e");
      await openAppSettings();
    }
  }

  void _showManageExternalStorageDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Требуется доступ к файлам'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Для сохранения тегов требуется разрешение "Управление всеми файлами".',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Как включить доступ:'),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.arrow_right, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Expanded(child: Text('Нажмите "Открыть настройки"')),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.arrow_right, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Expanded(child: Text('Найдите "Файлы и медиа" или "Хранилище"')),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.arrow_right, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Expanded(child: Text('Выберите "Разрешить управление всеми файлами"')),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.arrow_right, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Expanded(child: Text('Включите переключатель')),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.arrow_right, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Expanded(child: Text('Вернитесь в приложение')),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'После включения разрешения, вернитесь и попробуйте сохранить теги снова.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _openManageFilesSettings();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Включите разрешение и вернитесь в приложение'),
                    duration: Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Я включил',
                      onPressed: () {
                      },
                    ),
                  ),
                );
              }
            },
            icon: Icon(Icons.settings),
            label: Text('Открыть настройки'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initCurrentCover() async {
    try {
      final currentTag = await AudioTags.read(widget.filePath);
      
      if (currentTag?.pictures != null && currentTag!.pictures!.isNotEmpty) {
        final picture = currentTag.pictures!.first;
        setState(() {
          _selectedCover = picture.bytes;
        });
      }
    } catch (e) {
      print("Error loading current cover: $e");
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        
        if (bytes.length > 2 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Размер изображения не должен превышать 2MB')),
            );
          }
          return;
        }

        setState(() {
          _selectedCover = bytes;
          _hasCoverChanges = true;
        });
      }
    } catch (e) {
      print("Error picking cover image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе изображения: $e')),
        );
      }
    }
  }

  Future<void> _removeCover() async {
    setState(() {
      _selectedCover = null;
      _hasCoverChanges = true;
    });
  }

  Future<void> _saveTags() async {
  if (_isSaving || !_formKey.currentState!.validate()) return;

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Проверка разрешений...'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  final hasPermissions = await _checkAndRequestPermissions();
  if (!hasPermissions) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Недостаточно прав для сохранения тегов'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  setState(() {
    _isSaving = true;
  });


    try {
      int? yearValue;
      if (_yearController.text.isNotEmpty) {
        final yearInt = int.tryParse(_yearController.text);
        if (yearInt == null || yearInt <= 0) {
          yearValue = null;
        } else {
          yearValue = yearInt;
        }
      }

      String? year = widget.initialMetadata?.year?.toString();
      if (year != null) {
        final yearInt = int.tryParse(year);
        if (yearInt == null || yearInt <= 0) {
          year = null;
        }
      }

      final updatedTag = Tag(
        title: _titleController.text.isNotEmpty ? _titleController.text : null,
        trackArtist: _artistController.text.isNotEmpty ? _artistController.text : null,
        album: _albumController.text.isNotEmpty ? _albumController.text : null,
        genre: _genreController.text.isNotEmpty ? _genreController.text : null,
        year: yearValue,
        trackNumber: _trackNumberController.text.isNotEmpty ? int.tryParse(_trackNumberController.text) : null, 
        
        pictures: _selectedCover != null && _selectedCover!.isNotEmpty
            ? [Picture(
                bytes: _selectedCover!,
                mimeType: _getMimeType(_selectedCover!) ?? MimeType.jpeg,
                pictureType: PictureType.coverFront,
              )]
            : [],
      );

      print("Saving tags to: ${widget.filePath}");

      await AudioTags.write(
        widget.filePath,
        updatedTag      
      );

      await Future.delayed(Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(context).pop(true);
      }
  } catch (e) {
    print("Error saving tags: $e");
    
    if (e.toString().contains('Permission denied') || 
        e.toString().contains('code: 13') ||
        e.toString().contains('EACCES')) {
      if (mounted) {
        _showManageExternalStorageDialog();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения тегов: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }
}


  MimeType? _getMimeType(Uint8List bytes) {
    if (bytes.length >= 3) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return MimeType.jpeg;
      } else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return MimeType.png;
      } else if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return MimeType.bmp;
      }
    }
    return null; 
  }

  String? _validateYear(String? value) {
    if (value == null || value.isEmpty) return null;
    
    final year = int.tryParse(value);
    if (year == null) {
      return 'Введите корректный год';
    }
    if (year <= 0) {
      return 'Год должен быть положительным числом';
    }
    if (year > 2100) {
      return 'Введите год, не превышающий 2100';
    }
    return null;
  }

  String? _validateTrackNumber(String? value) {
    if (value == null || value.isEmpty) return null;
    
    final track = int.tryParse(value);
    if (track == null) {
      return 'Введите корректный номер трека';
    }
    if (track <= 0) {
      return 'Номер трека должен быть положительным';
    }
    return null;
  }

  Widget _buildCoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Обложка альбома',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              if (_selectedCover != null)
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedCover!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholderCover();
                      },
                    ),
                  ),
                )
              else
                _buildPlaceholderCover(),
              
              SizedBox(height: 16),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickCoverImage,
                    icon: Icon(Icons.photo_library, size: 20),
                    label: Text('Выбрать'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  
                  if (_selectedCover != null)
                    ElevatedButton.icon(
                      onPressed: _removeCover,
                      icon: Icon(Icons.delete, size: 20),
                      label: Text('Удалить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              
              SizedBox(height: 8),
              Text(
                'Поддерживаемые форматы: JPG, PNG, BMP\nМаксимальный размер: 2MB',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.album,
            size: 40,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 8),
          Text(
            'Нет обложки',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Редактировать теги'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCoverSection(),
              
              _buildTextField(_titleController, 'Название трека', Icons.title),
              SizedBox(height: 12),
              _buildTextField(_artistController, 'Исполнитель', Icons.person),
              SizedBox(height: 12),
              _buildTextField(_albumController, 'Альбом', Icons.album),
              SizedBox(height: 12),
              _buildTextField(_genreController, 'Жанр', Icons.music_note),
              SizedBox(height: 12),
              _buildNumberField(
                _yearController, 
                'Год', 
                Icons.calendar_today, 
                _validateYear,
              ),
              SizedBox(height: 12),
              _buildNumberField(
                _trackNumberController, 
                'Номер трека', 
                Icons.format_list_numbered, 
                _validateTrackNumber,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveTags,
          child: _isSaving 
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildNumberField(
    TextEditingController controller, 
    String label, 
    IconData icon,
    String? Function(String?) validator,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}
