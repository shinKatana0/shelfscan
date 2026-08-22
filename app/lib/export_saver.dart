/// Saving a rendered export to wherever the platform keeps files.
///
/// Exporters in `shelfscan_core` return strings and nothing else
/// (ARCHITECTURE.md platform boundary); everything below -- save dialogs,
/// temp files, share sheets -- is shell work and lives here so that the
/// review screen stays testable with a fake backend.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// What actually happened to the rendered export.
enum SaveKind {
  /// Written to a path the user chose (desktop save dialog).
  savedToFile,

  /// Handed to the system share sheet (Android).
  shared,

  /// User backed out of the dialog / share sheet.
  cancelled,

  /// The platform refused; [SaveOutcome.error] carries the reason.
  failed,
}

class SaveOutcome {
  const SaveOutcome(this.kind, {this.path, this.error});

  const SaveOutcome.savedToFile(String path)
      : this(SaveKind.savedToFile, path: path);
  const SaveOutcome.shared(String path) : this(SaveKind.shared, path: path);
  const SaveOutcome.cancelled() : this(SaveKind.cancelled);
  const SaveOutcome.failed(String error) : this(SaveKind.failed, error: error);

  final SaveKind kind;

  /// Where it landed. Absolute path on desktop, temp path when shared.
  final String? path;
  final String? error;
}

/// Injection seam: the review screen depends on this, tests supply a fake.
abstract class ExportSaver {
  const ExportSaver();

  /// [suggestedName] is the pre-filled file name, e.g. `shelf.xcoll`.
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  });
}

/// Real implementation: save dialog on desktop, share sheet on mobile.
class PlatformExportSaver extends ExportSaver {
  const PlatformExportSaver();

  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await _share(suggestedName, extension, content);
      }
      return await _saveDialog(suggestedName, extension, content);
    } on Object catch (e) {
      return SaveOutcome.failed('$e');
    }
  }

  Future<SaveOutcome> _saveDialog(
      String suggestedName, String extension, String content) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: 'shelfscan export', extensions: [extension]),
      ],
    );
    if (location == null) return const SaveOutcome.cancelled();
    final file = File(location.path);
    await file.writeAsString(content, flush: true);
    return SaveOutcome.savedToFile(file.path);
  }

  /// Android has no stable user-visible file system to write into, so the
  /// export goes to a temp file that is immediately handed to the share
  /// sheet -- the user picks the destination app from there.
  Future<SaveOutcome> _share(
      String suggestedName, String extension, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$suggestedName');
    await file.writeAsString(content, flush: true);
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeTypeFor(extension))],
      subject: suggestedName,
    );
    if (result.status == ShareResultStatus.dismissed) {
      return const SaveOutcome.cancelled();
    }
    return SaveOutcome.shared(file.path);
  }
}

/// `.xcoll` is JSON (external contract, see TonkatsuExporter).
String mimeTypeFor(String extension) => switch (extension) {
      'csv' => 'text/csv',
      'xcoll' || 'json' => 'application/json',
      _ => 'application/octet-stream',
    };
