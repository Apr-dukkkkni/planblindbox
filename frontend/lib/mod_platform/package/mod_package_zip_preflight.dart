import 'dart:convert';
import 'dart:typed_data';

import 'mod_package_models.dart';

/// Reads the ZIP central directory before decompression so declared sizes,
/// names, entry types and compression methods are bounded before any payload
/// is inflated. ZIP64 and multi-disk archives are intentionally not supported:
/// the V1 package limits are far below classic ZIP limits.
class ModPackageZipPreflight {
  const ModPackageZipPreflight();

  List<ModZipEntryMetadata> inspect(List<int> input) {
    if (input.length < 22 || input.length > ModPackageLimits.maxArchiveBytes) {
      throw const FormatException('ZIP 文件大小无效或超过 50 MiB');
    }
    final bytes = input is Uint8List ? input : Uint8List.fromList(input);
    final data = ByteData.sublistView(bytes);
    final eocd = _findEndOfCentralDirectory(data);
    final disk = data.getUint16(eocd + 4, Endian.little);
    final centralDisk = data.getUint16(eocd + 6, Endian.little);
    final entriesOnDisk = data.getUint16(eocd + 8, Endian.little);
    final entryCount = data.getUint16(eocd + 10, Endian.little);
    final centralSize = data.getUint32(eocd + 12, Endian.little);
    final centralOffset = data.getUint32(eocd + 16, Endian.little);
    final commentLength = data.getUint16(eocd + 20, Endian.little);

    if (disk != 0 || centralDisk != 0 || entriesOnDisk != entryCount) {
      throw const FormatException('不支持分卷或多磁盘 ZIP');
    }
    if (entryCount == 0xffff || centralSize == 0xffffffff ||
        centralOffset == 0xffffffff) {
      throw const FormatException('V1 内容包不支持 ZIP64');
    }
    if (entryCount == 0 || entryCount > ModPackageLimits.maxFiles) {
      throw const FormatException('ZIP 文件数量无效或超过 256 个');
    }
    if (eocd + 22 + commentLength != bytes.length ||
        centralOffset + centralSize != eocd ||
        centralOffset < 0 || centralSize < 0 ||
        centralOffset + centralSize > bytes.length) {
      throw const FormatException('ZIP 中央目录边界无效');
    }

    final entries = <ModZipEntryMetadata>[];
    final seen = <String>{};
    var cursor = centralOffset;
    var expandedTotal = 0;
    final localRanges = <(int, int)>[];
    for (var index = 0; index < entryCount; index++) {
      _requireRange(cursor, 46, centralOffset + centralSize);
      if (data.getUint32(cursor, Endian.little) != 0x02014b50) {
        throw const FormatException('ZIP 中央目录记录损坏');
      }
      final madeBy = data.getUint16(cursor + 4, Endian.little);
      final flags = data.getUint16(cursor + 8, Endian.little);
      final method = data.getUint16(cursor + 10, Endian.little);
      final crc32 = data.getUint32(cursor + 16, Endian.little);
      final compressedSize = data.getUint32(cursor + 20, Endian.little);
      final uncompressedSize = data.getUint32(cursor + 24, Endian.little);
      final nameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final entryCommentLength = data.getUint16(cursor + 32, Endian.little);
      final startDisk = data.getUint16(cursor + 34, Endian.little);
      final externalAttributes = data.getUint32(cursor + 38, Endian.little);
      final localHeaderOffset = data.getUint32(cursor + 42, Endian.little);
      final recordLength = 46 + nameLength + extraLength + entryCommentLength;
      _requireRange(cursor, recordLength, centralOffset + centralSize);
      if (nameLength == 0 || startDisk != 0 || compressedSize == 0xffffffff ||
          uncompressedSize == 0xffffffff || localHeaderOffset == 0xffffffff) {
        throw const FormatException('ZIP 条目头无效或使用 ZIP64');
      }
      if ((flags & 0x0001) != 0 || (flags & 0x0040) != 0 ||
          (flags & 0x2000) != 0) {
        throw const FormatException('不支持加密 ZIP 条目');
      }
      // Only UTF-8 names (or plain ASCII names) are accepted. This avoids
      // ambiguous legacy code-page decoding across platforms.
      final nameBytes = bytes.sublist(cursor + 46, cursor + 46 + nameLength);
      if ((flags & 0x0800) == 0 && nameBytes.any((b) => b > 0x7f)) {
        throw const FormatException('ZIP 文件名必须使用 UTF-8 编码');
      }
      final name = utf8.decode(nameBytes, allowMalformed: false);
      final isDirectory = name.endsWith('/');
      final normalizedName = isDirectory ? name.substring(0, name.length - 1) : name;
      _validateArchivePath(normalizedName);
      final foldedName = normalizedName.toLowerCase();
      if (!seen.add(foldedName)) {
        throw FormatException('ZIP 存在重复文件名：$name');
      }

      if (method != 0 && method != 8) {
        throw FormatException('ZIP 压缩方式不受支持：$name');
      }
      final allowedFlags = method == 8 ? 0x080e : 0x0808;
      if ((flags & ~allowedFlags) != 0) {
        throw FormatException('ZIP 条目标志位不受支持：$name');
      }
      if (isDirectory && (compressedSize != 0 || uncompressedSize != 0)) {
        throw FormatException('目录条目不能包含文件内容：$name');
      }
      if (!isDirectory) {
        if (uncompressedSize > ModPackageLimits.maxFileBytes) {
          throw FormatException('ZIP 单个文件超过 20 MiB：$name');
        }
        expandedTotal += uncompressedSize;
        if (expandedTotal > ModPackageLimits.maxExpandedBytes) {
          throw const FormatException('ZIP 解压后总大小超过 100 MiB');
        }
      }

      final platform = madeBy >> 8;
      final unixMode = (externalAttributes >> 16) & 0xffff;
      final unixType = unixMode & 0xf000;
      if (platform == 3 && unixType == 0xa000) {
        throw FormatException('不允许符号链接：$name');
      }
      if (platform == 3 && unixType != 0 &&
          unixType != 0x8000 && unixType != 0x4000) {
        throw FormatException('不允许特殊文件类型：$name');
      }

      final localDataEnd = _validateLocalHeader(
        data: data,
        bytes: bytes,
        offset: localHeaderOffset,
        centralOffset: centralOffset,
        expectedName: nameBytes,
        expectedFlags: flags,
        expectedMethod: method,
        expectedCrc32: crc32,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        hasDataDescriptor: (flags & 0x0008) != 0,
      );
      localRanges.add((localHeaderOffset, localDataEnd));
      entries.add(ModZipEntryMetadata(
        name: normalizedName,
        isDirectory: isDirectory,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        crc32: crc32,
      ));
      cursor += recordLength;
    }
    if (cursor != centralOffset + centralSize) {
      throw const FormatException('ZIP 中央目录包含多余或损坏的数据');
    }
    localRanges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < localRanges.length; i++) {
      if (localRanges[i].$1 < localRanges[i - 1].$2) {
        throw const FormatException('ZIP 本地条目数据区域发生重叠');
      }
    }
    _rejectFileDirectoryCollisions(entries);
    return List<ModZipEntryMetadata>.unmodifiable(entries);
  }

  int _findEndOfCentralDirectory(ByteData data) {
    final minOffset = (data.lengthInBytes - 22 - 65535).clamp(0, data.lengthInBytes);
    for (var offset = data.lengthInBytes - 22; offset >= minOffset; offset--) {
      if (data.getUint32(offset, Endian.little) == 0x06054b50) {
        final commentLength = data.getUint16(offset + 20, Endian.little);
        if (offset + 22 + commentLength == data.lengthInBytes) return offset;
      }
    }
    throw const FormatException('找不到有效的 ZIP 结束记录');
  }

  int _validateLocalHeader({
    required ByteData data,
    required Uint8List bytes,
    required int offset,
    required int centralOffset,
    required List<int> expectedName,
    required int expectedFlags,
    required int expectedMethod,
    required int expectedCrc32,
    required int compressedSize,
    required int uncompressedSize,
    required bool hasDataDescriptor,
  }) {
    _requireRange(offset, 30, centralOffset);
    if (data.getUint32(offset, Endian.little) != 0x04034b50) {
      throw const FormatException('ZIP 本地文件头损坏');
    }
    final flags = data.getUint16(offset + 6, Endian.little);
    final method = data.getUint16(offset + 8, Endian.little);
    final localCrc32 = data.getUint32(offset + 14, Endian.little);
    final localCompressedSize = data.getUint32(offset + 18, Endian.little);
    final localUncompressedSize = data.getUint32(offset + 22, Endian.little);
    final nameLength = data.getUint16(offset + 26, Endian.little);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    if (flags != expectedFlags || method != expectedMethod) {
      throw const FormatException('ZIP 本地头与中央目录不一致');
    }
    final dataStart = offset + 30 + nameLength + extraLength;
    _requireRange(offset, 30 + nameLength + extraLength, centralOffset);
    final localName = bytes.sublist(offset + 30, offset + 30 + nameLength);
    if (!_sameBytes(localName, expectedName)) {
      throw const FormatException('ZIP 本地文件名与中央目录不一致');
    }
    _requireRange(dataStart, compressedSize, centralOffset);
    var end = dataStart + compressedSize;
    if (!hasDataDescriptor) {
      if (localCrc32 != expectedCrc32 ||
          localCompressedSize != compressedSize ||
          localUncompressedSize != uncompressedSize) {
        throw const FormatException('ZIP 本地头的长度或 CRC 与中央目录不一致');
      }
    } else {
      _requireRange(end, 12, centralOffset);
      var descriptorOffset = end;
      var hasSignature = false;
      if (data.getUint32(end, Endian.little) == 0x08074b50 &&
          end + 16 <= centralOffset &&
          data.getUint32(end + 4, Endian.little) == expectedCrc32 &&
          data.getUint32(end + 8, Endian.little) == compressedSize &&
          data.getUint32(end + 12, Endian.little) == uncompressedSize) {
        hasSignature = true;
        descriptorOffset += 4;
      }
      final descriptorCrc = data.getUint32(descriptorOffset, Endian.little);
      final descriptorCompressed = data.getUint32(descriptorOffset + 4, Endian.little);
      final descriptorUncompressed = data.getUint32(descriptorOffset + 8, Endian.little);
      if (descriptorCrc != expectedCrc32 ||
          descriptorCompressed != compressedSize ||
          descriptorUncompressed != uncompressedSize) {
        throw const FormatException('ZIP 数据描述符与中央目录不一致');
      }
      end = descriptorOffset + 12;
      if (hasSignature) _requireRange(end - 16, 16, centralOffset);
    }
    return end;
  }

  void _validateArchivePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\') ||
        path.contains(':') || path.contains('\u0000')) {
      throw FormatException('ZIP 路径不安全：$path');
    }
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..' ||
          !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment) ||
          segment.endsWith('.')) {
        throw FormatException('ZIP 路径不安全：$path');
      }
      final stem = segment.split('.').first.toUpperCase();
      if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
        throw FormatException('ZIP 路径包含 Windows 保留名称：$path');
      }
    }
  }

  void _rejectFileDirectoryCollisions(List<ModZipEntryMetadata> entries) {
    final files = entries.where((entry) => !entry.isDirectory)
        .map((entry) => entry.name.toLowerCase()).toSet();
    for (final entry in entries) {
      final parts = entry.name.toLowerCase().split('/');
      for (var i = 1; i < parts.length; i++) {
        final parent = parts.take(i).join('/');
        if (files.contains(parent)) {
          throw FormatException('ZIP 文件与目录路径冲突：${entry.name}');
        }
      }
    }
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _requireRange(int offset, int length, int limit) {
    if (offset < 0 || length < 0 || offset > limit || length > limit - offset) {
      throw const FormatException('ZIP 条目越界');
    }
  }
}

class ModZipEntryMetadata {
  const ModZipEntryMetadata({
    required this.name,
    required this.isDirectory,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
  });

  final String name;
  final bool isDirectory;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
}
