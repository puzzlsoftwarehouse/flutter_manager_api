import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class BlurHashEncoder {
  static const int numCompX = 4;
  static const int numCompY = 3;
  static const int thumbnailSize = 100;
  static const int maxEncodeBytes = 20 * 1024 * 1024;

  static const Set<String> _skipExtensions = <String>{'heic', 'heif'};
  static const Set<String> _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'tif',
    'tiff',
  };

  BlurHashEncoder._();

  static Future<String?> resolve({
    required XFile file,
    String? existingBlurHash,
    String? mimetype,
    String? filename,
    String? contentDatumTypeSlug,
    int? fileSize,
  }) async {
    if (existingBlurHash != null && existingBlurHash.isNotEmpty) {
      return existingBlurHash;
    }

    final String resolvedFilename = filename ?? file.name;
    final String? resolvedMimetype = mimetype ?? file.mimeType;

    if (!_shouldEncode(
      mimetype: resolvedMimetype,
      filename: resolvedFilename,
      contentDatumTypeSlug: contentDatumTypeSlug,
    )) {
      return null;
    }

    try {
      final int resolvedSize = fileSize ?? await file.length();
      if (resolvedSize <= 0 || resolvedSize > maxEncodeBytes) {
        return null;
      }

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length > maxEncodeBytes) {
        return null;
      }
      return await compute(_encodeBytes, bytes);
    } catch (_) {
      return null;
    }
  }

  static bool _shouldEncode({
    required String? mimetype,
    required String filename,
    required String? contentDatumTypeSlug,
  }) {
    final String extension = _extensionOf(filename);
    if (_skipExtensions.contains(extension)) {
      return false;
    }

    final String? normalizedMime = mimetype?.toLowerCase();
    if (normalizedMime != null && normalizedMime.startsWith('image/')) {
      if (normalizedMime.contains('heic') || normalizedMime.contains('heif')) {
        return false;
      }
      return true;
    }

    if (_imageExtensions.contains(extension)) {
      return true;
    }

    final String? datumSlug = contentDatumTypeSlug?.toLowerCase();
    if (datumSlug != null && _imageExtensions.contains(datumSlug)) {
      return true;
    }

    return false;
  }

  static String _extensionOf(String filename) {
    final int dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }
}

String? _encodeBytes(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }

  final img.Image thumbnail = img.copyResize(
    decoded,
    width: BlurHashEncoder.thumbnailSize,
    height: BlurHashEncoder.thumbnailSize,
    maintainAspect: true,
  );

  return BlurHash.encode(
    thumbnail,
    numCompX: BlurHashEncoder.numCompX,
    numCompY: BlurHashEncoder.numCompY,
  ).hash;
}
