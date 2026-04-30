import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class PdfBytesParser {
  PdfBytesParser._();

  static const List<int> _pdfHeader = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];

  static const Set<String> _preferredPdfKeys = <String>{
    'pdfbytes',
    'pdf_bytes',
    'pdf',
    'pdfbase64',
    'pdf_base64',
    'archivopdf',
    'archivo_pdf',
    'adjuntopdf',
    'adjunto_pdf',
    'evidenciapdf',
    'evidencia_pdf',
    'documentopdf',
    'documento_pdf',
  };

  static Uint8List? parse(Object? raw, {int maxDepth = 10}) {
    final Uint8List? parsed = _parseInternal(raw, depth: 0, maxDepth: maxDepth);
    if (parsed == null || parsed.isEmpty) {
      return null;
    }
    return looksLikePdf(parsed) ? parsed : null;
  }

  static bool looksLikePdf(Uint8List bytes) {
    if (bytes.length < _pdfHeader.length) {
      return false;
    }

    final int maxScan = bytes.length < 1024 ? bytes.length : 1024;
    for (int i = 0; i <= maxScan - _pdfHeader.length; i++) {
      bool matches = true;
      for (int j = 0; j < _pdfHeader.length; j++) {
        if (bytes[i + j] != _pdfHeader[j]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return true;
      }
    }

    return false;
  }

  static Uint8List? parseFromMapByLikelyKeys(Map<String, dynamic> data) {
    // First pass: strict known PDF field names.
    for (final MapEntry<String, dynamic> entry in data.entries) {
      final String normalized = _normalizeKey(entry.key);
      if (_preferredPdfKeys.contains(normalized)) {
        final Uint8List? parsed = parse(entry.value);
        if (parsed != null && parsed.isNotEmpty) {
          return parsed;
        }
      }
    }

    // Second pass: fields that mention common legacy names.
    for (final MapEntry<String, dynamic> entry in data.entries) {
      final String normalized = _normalizeKey(entry.key);
      final bool likelyPdfField =
          normalized.contains('pdf') ||
          normalized.contains('archivo') ||
          normalized.contains('adjunto') ||
          normalized.contains('evidencia') ||
          normalized.contains('documento');
      if (!likelyPdfField) {
        continue;
      }
      final Uint8List? parsed = parse(entry.value);
      if (parsed != null && parsed.isNotEmpty) {
        return parsed;
      }
    }

    return null;
  }

  static Uint8List? _parseInternal(
    Object? raw, {
    required int depth,
    required int maxDepth,
  }) {
    if (raw == null || raw is bool || depth > maxDepth) {
      return null;
    }

    if (raw is Blob) {
      return raw.bytes.isEmpty ? null : raw.bytes;
    }

    if (raw is Uint8List) {
      return raw.isEmpty ? null : raw;
    }

    if (raw is ByteBuffer) {
      final Uint8List bytes = raw.asUint8List();
      return bytes.isEmpty ? null : bytes;
    }

    if (raw is List<int>) {
      if (raw.isEmpty) {
        return null;
      }
      return Uint8List.fromList(raw);
    }

    if (raw is Iterable) {
      final List<int> bytes = <int>[];
      for (final Object? item in raw) {
        if (item is int) {
          bytes.add(item);
          continue;
        }
        if (item is num) {
          bytes.add(item.toInt());
          continue;
        }

        final Uint8List? nested = _parseInternal(
          item,
          depth: depth + 1,
          maxDepth: maxDepth,
        );
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
        return null;
      }
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    }

    if (raw is Map) {
      final Map<String, dynamic> normalizedMap = <String, dynamic>{};
      for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
        normalizedMap[entry.key.toString()] = entry.value;
      }

      // Prioritize direct known keys first to avoid false positives.
      for (final String key in _preferredPdfKeys) {
        for (final MapEntry<String, dynamic> entry in normalizedMap.entries) {
          if (_normalizeKey(entry.key) != key) {
            continue;
          }
          final Uint8List? parsed = _parseInternal(
            entry.value,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        }
      }

      // Common wrappers from platform/channel serialization.
      for (final String key in <String>['bytes', 'data', '_bytes', 'blob', 'value']) {
        if (!normalizedMap.containsKey(key)) {
          continue;
        }
        final Uint8List? parsed = _parseInternal(
          normalizedMap[key],
          depth: depth + 1,
          maxDepth: maxDepth,
        );
        if (parsed != null && parsed.isNotEmpty) {
          return parsed;
        }
      }

      for (final dynamic value in normalizedMap.values) {
        final Uint8List? parsed = _parseInternal(
          value,
          depth: depth + 1,
          maxDepth: maxDepth,
        );
        if (parsed != null && parsed.isNotEmpty) {
          return parsed;
        }
      }

      return null;
    }

    if (raw is String && raw.trim().isNotEmpty) {
      final String normalized = raw.trim();
      final int dataUriIndex = normalized.indexOf('base64,');
      final String payload = dataUriIndex >= 0
          ? normalized.substring(dataUriIndex + 7)
          : normalized;
      try {
        final Uint8List decoded = base64Decode(payload);
        return decoded.isEmpty ? null : decoded;
      } catch (_) {
        // Try URL-safe base64 variant.
        final String urlSafe = payload.replaceAll('-', '+').replaceAll('_', '/');
        try {
          final Uint8List decoded = base64Decode(urlSafe);
          return decoded.isEmpty ? null : decoded;
        } catch (_) {
          return null;
        }
      }
    }

    return null;
  }

  static String _normalizeKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }
}


