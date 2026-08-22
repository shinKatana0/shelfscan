/// A folder of games as a scan input: what the shell enumerates, which source
/// reads each entry, and which folders it refuses to enumerate quietly.
///
/// The filesystem half of T-0155's seam. `shelfscan_core` imports no
/// `dart:io` (ARCHITECTURE.md), so walking the directory and reading the
/// metadata text is the shell's, and every judgement about a name is core's.
library;

import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';

/// The two folder sources with one owner per entry.
///
/// Routed by name rather than tried in turn: `goggame-*.info` is the metadata
/// source's, everything else the filename source's. A fallback would overwrite
/// a real metadata decline -- DLC, unparsable JSON -- with `not a game file`,
/// which is what [FilenameSource] answers about a `.info` on purpose, having
/// handed it over (T-0158).
class InstalledGameSource implements DetectionSource {
  const InstalledGameSource();

  static const _metadata = GogMetadataSource();
  static const _names = FilenameSource();

  @override
  SourceReading read(SourceEntry entry) =>
      GogMetadataSource.fileName.hasMatch(entry.name)
          ? _metadata.read(entry)
          : _names.read(entry);
}

/// One chosen folder and the entries a scan will be handed for it.
class GameFolder {
  const GameFolder(
      {required this.path, required this.name, required this.entries});

  /// As the picker returned it: what the user recognises the folder by, and
  /// the identity two picks are compared on.
  final String path;

  /// The last segment of [path]: what the review screen calls the folder.
  ///
  /// Deliberately not any entry's [SourceEntry.container] since T-0193 -- it
  /// names the collection, not a game, and a container is read as a title.
  final String name;

  final List<SourceEntry> entries;
}

/// The last segment of [path], with either platform's separator.
String folderName(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  final cut = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  final name = cut < 0 ? trimmed : trimmed.substring(cut + 1);
  return name.isEmpty ? path : name;
}

/// Folders that hold whatever was put in them, so the games in one are a
/// minority of what a scan would read. Folded, matched against the last
/// segment only.
const _mixedFolders = {
  'downloads',
  'download',
  'desktop',
  'documents',
  'my documents',
  'pictures',
  'music',
  'videos',
  'onedrive',
  'dropbox',
  'appdata',
  'temp',
  'tmp',
  'program files',
  'program files (x86)',
  'windows',
  'system32',
  'users',
};

/// The measurement this whole control is shaped around (T-0158).
const _measurement =
    'Nothing in a file name separates a game installer from an application '
    'one: over a Downloads folder this titles every installer it finds, and '
    'not one of them is a game -- it reads NoteWellSetup.exe exactly as it '
    'reads setup_moor_1.9.exe (T-0158).';

/// Why the chosen folder is probably not the one the user meant, or null.
///
/// Asked before the folder is added and answered to the user's face, because
/// the alternative is a review screen of plausible non-games and no way to
/// tell from it that the folder was the mistake. It questions rather than
/// refuses: a user who does keep their games in `Downloads` is wrong about
/// tidiness, not about their own machine.
String? folderConcern(String path) {
  final name = folderName(path);
  if (_isRoot(path)) {
    return 'That is the whole of $name. Every file and folder in it would be '
        'read as the name of a game. $_measurement';
  }
  if (_mixedFolders.contains(name.toLowerCase())) {
    return '$name is where files land rather than where games are installed. '
        '$_measurement';
  }
  return null;
}

bool _isRoot(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  return trimmed.isEmpty || RegExp(r'^[A-Za-z]:$').hasMatch(trimmed);
}

/// What the pipeline gets handed for one folder.
///
/// **One level down and no further.** An installed game holds hundreds of
/// files, and at depth 2 every one of them is an entry and nearly all of them
/// a [DeclinedEntry]: a hundred games would produce a five-figure skipped
/// count, which is the "fifty lines is worse than silence" failure at scale.
/// At depth 1 the count is the folder's own child count.
///
/// A directory with no metadata in it is handed over under its own name, which
/// is how a non-GoG install is titled at all. `Screenshots`, `Saves` and
/// `New Folder` used to come back as titles here, because the generic-name
/// list was consulted only for [SourceEntry.container]; T-0174 moved the
/// consultation to cover both fields, so they decline instead.
///
/// **The chosen folder is not a container (T-0193).** [SourceEntry.container]
/// is a parent whose name may title an entry that carries none of its own, and
/// that fallback is written for a game's own folder. The folder the user
/// pointed at names the collection instead: handing it over gave `New Folder`,
/// `Screenshots` and `Saves` one title each -- all three the chosen folder's --
/// and stage 2 merged them into a single row that reads like a real game
/// (measured 2026-08-16). Children of the chosen folder therefore go over with
/// no container, and one that titles nothing declines by name onto the skipped
/// list. The chosen folder's name still travels in the `goggame-*.info` branch
/// above, where the folder is PROVEN to be one game's own.
///
/// The cost, deliberately paid: a scan pointed at a single non-GoG install no
/// longer takes the title off that install's own folder -- `Dusk-Rail 2` came
/// back from `Screenshots`, `Saves` and `data`, and now comes back as `hbl2`,
/// off `hbl2.exe`. A wrong title a human can see, against a right one bought by
/// a rule that names a game after any folder of junk.
///
/// A directory the folder's own name cannot title is not given up on: the one
/// installer inside it is handed over in its place ([installerNamingFolder]).
/// Two triggers, not the one this shipped with -- a name that titles nothing
/// (T-0178), which is `New Folder/setup_harbour_lantern_1.6.15.exe`, the case the
/// owner reported; and a name that DOES title a game, given up when the one
/// unmistakable downloaded installer inside contradicts it outright (T-0183),
/// which is what reaches a locale-generated name no list in core holds. It
/// costs no read the metadata scan above has not made already and no entry at
/// all -- one per subdirectory, before and after.
///
/// A read that fails is never dropped: an unlistable directory falls back to
/// its own name, and an unreadable `goggame-*.info` is handed over without
/// content, which the metadata source declines by name.
Future<GameFolder> readGameFolder(String path) async {
  final name = folderName(path);
  final children = await _children(Directory(path));
  final entries = <SourceEntry>[];

  // A folder holding a `goggame-*.info` IS one game's folder -- GOG writes it
  // into "the root folder of the game" (docs.gog.com/sdk-dlc-discovery/) --
  // so its subdirectories are that game's screenshots and saves, not games.
  final own = _metadataIn(children);
  if (own.isNotEmpty) {
    for (final file in own) {
      entries.add(await _metadataEntry(file, name));
    }
    return GameFolder(path: path, name: name, entries: entries);
  }

  for (final child in children) {
    if (child is Directory) {
      final childName = _lastSegment(child.path);
      final contents = await _children(child);
      final metadata = _metadataIn(contents);
      if (metadata.isEmpty) {
        final inside = installerNamingFolder(childName, [
          for (final file in contents)
            if (file is File) _lastSegment(file.path)
        ]);
        entries.add(inside == null
            ? SourceEntry(name: childName)
            : SourceEntry(name: inside, container: childName));
        continue;
      }
      for (final file in metadata) {
        entries.add(await _metadataEntry(file, childName));
      }
    } else if (child is File) {
      entries.add(SourceEntry(name: _lastSegment(child.path)));
    }
  }
  return GameFolder(path: path, name: name, entries: entries);
}

/// Sorted, because a directory listing is in no defined order and the entries
/// keep their order all the way to the review screen's rows.
Future<List<FileSystemEntity>> _children(Directory directory) async {
  try {
    final children = await directory.list(followLinks: false).toList();
    children.sort((a, b) => a.path.compareTo(b.path));
    return children;
  } on FileSystemException {
    return const [];
  }
}

List<File> _metadataIn(List<FileSystemEntity> children) => [
      for (final child in children)
        if (child is File &&
            GogMetadataSource.fileName.hasMatch(_lastSegment(child.path)))
          child,
    ];

Future<SourceEntry> _metadataEntry(File file, String container) async {
  String? content;
  try {
    content = await file.readAsString();
  } on Object {
    content = null;
  }
  return SourceEntry(
      name: _lastSegment(file.path), container: container, content: content);
}

String _lastSegment(String path) =>
    path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1);
