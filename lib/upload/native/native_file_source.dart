import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

class NativeFileSource {
  final XFile file;

  const NativeFileSource(this.file);

  bool get hasLocalFileOnDisk {
    final String filePath = file.path;
    if (filePath.isEmpty || !_isFilesystemPath(filePath)) {
      return false;
    }
    return File(filePath).existsSync();
  }

  Future<Stream<List<int>>> openChunkStream({
    required int offset,
    required int length,
  }) async {
    if (hasLocalFileOnDisk) {
      return File(file.path).openRead(offset, offset + length);
    }

    final Uint8List bytes = await file.readAsBytes();
    final int end = (offset + length).clamp(0, bytes.length);
    final int start = offset.clamp(0, bytes.length);
    return Stream<List<int>>.value(bytes.sublist(start, end));
  }

  Future<Uint8List?> readInMemoryBytesIfNeeded() async {
    if (hasLocalFileOnDisk) {
      return null;
    }
    return file.readAsBytes();
  }

  bool _isFilesystemPath(String path) {
    if (path.startsWith('/')) {
      return true;
    }

    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path)) {
      return true;
    }

    return false;
  }
}
