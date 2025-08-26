import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;


class MediaService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takeFrontCameraPhoto() {
    return _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
  }

  Future<Uint8List> readBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('Photo file not found');
    return file.readAsBytes();
  }

  Future<Uint8List> compressForFirestore(Uint8List input, {required int maxBytes}) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) throw Exception('Invalid image');

    int width = decoded.width;
    int targetW = width > 800 ? 800 : width;
    int quality = 70;

    Uint8List out = _encodeJpg(decoded, targetW, quality);
    while (out.lengthInBytes > maxBytes) {
      if (quality > 30) {
        quality -= 10;
      } else if (targetW > 400) {
        targetW = math.max(400, targetW - 100);
        quality = 70;
      } else if (targetW > 300) {
        targetW = math.max(300, targetW - 50);
        quality = 60;
      } else if (quality > 20) {
        quality -= 5;
      } else {
        targetW = math.max(200, targetW - 50);
        quality = 30;
      }
      out = _encodeJpg(decoded, targetW, quality);
      if (targetW <= 200 && quality <= 20) break;
    }
    return out;
  }

  Future<Uint8List> makeThumb(Uint8List input, {required int maxBytes}) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) throw Exception('Invalid image');
    int w = 144;
    int q = 60;
    Uint8List out = Uint8List.fromList(img.encodeJpg(img.copyResize(decoded, width: w), quality: q));
    while (out.lengthInBytes > maxBytes && (q > 40 || w > 96)) {
      if (q > 40) q -= 5;
      if (w > 96) w -= 16;
      out = Uint8List.fromList(img.encodeJpg(img.copyResize(decoded, width: w), quality: q));
    }
    return out;
  }

  void cleanupTemp(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Uint8List _encodeJpg(img.Image decoded, int width, int quality) {
    final resized = img.copyResize(decoded, width: width);
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
}