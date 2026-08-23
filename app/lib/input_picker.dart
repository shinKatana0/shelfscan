/// Asking the user for the things a scan runs on.
///
/// Two of the three inputs have to be chosen: the photographs and the folder
/// of installed games (the GOG library has one known path and nothing to
/// pick). Which dialog opens, and how it is asked, is platform work and lives
/// here for the same reason `export_saver.dart` exists -- so the scan screen
/// depends on an interface this project owns rather than on a plugin, and the
/// plugin has exactly one caller in the app.
///
/// **What this deliberately does not carry.** The dialog's file-type filter is
/// not a parameter: "photographs" already says which extensions, and the
/// answer is [pickerExtensions] for every caller there will ever be. Neither
/// is anything the app has never needed -- an initial directory, a
/// multi-select flag, streams, sizes, or the paths a picked file may or may
/// not have on Android. What does cross is the folder prompt, because the
/// wording is steering rather than decoration (T-0158): the control, the
/// dialog and the confirmation all have to name the same folder, so the caller
/// says it once.
library;

import 'package:file_picker/file_picker.dart';

import 'photo_files.dart';

/// Injection seam: the scan screen depends on this, tests supply a fake.
abstract class InputPicker {
  const InputPicker();

  /// The photographs to scan, each as the bytes it actually is.
  ///
  /// Null when the user closed the dialog without choosing; an empty list is
  /// a choice of nothing, and the two are not the same answer to the screen.
  Future<List<PickedFile>?> pickPhotos();

  /// A folder to read installed games out of, or null when the user closed
  /// the dialog without choosing. [prompt] is what the dialog asks for.
  Future<String?> pickFolder({required String prompt});
}

/// The real dialogs, and the only place in `app/lib` that names the plugin.
class PlatformInputPicker extends InputPicker {
  const PlatformInputPicker();

  @override
  Future<List<PickedFile>?> pickPhotos() async {
    // FileType.custom rather than FileType.image: the Windows dialog's own
    // image filter hides .heic, so the phone's HEIC photos could not even be
    // selected (T-0039).
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: pickerExtensions,
      allowMultiple: true,
      withData: true, // bytes, not paths: Android may not expose real paths
    );
    if (result == null) return null;
    return [
      for (final file in result.files)
        if (file.bytes case final bytes?) (name: file.name, bytes: bytes)
    ];
  }

  @override
  Future<String?> pickFolder({required String prompt}) =>
      FilePicker.platform.getDirectoryPath(dialogTitle: prompt);
}
