/// shelfscan core: pure Dart pipeline, no Flutter dependencies.
///
/// The Flutter app and the CLI are both thin shells over this package.
library;

export 'src/exporters/exporters.dart';
export 'src/http_timeout.dart';
export 'src/models.dart';
export 'src/orchestrator.dart';
export 'src/photo_format.dart';
export 'src/providers/igdb.dart';
export 'src/providers/ollama_vision.dart';
export 'src/providers/openai_compatible_vision.dart';
export 'src/providers/tmdb.dart';
export 'src/providers/vision.dart';
export 'src/sources/filename_source.dart';
export 'src/sources/gog_library.dart';
export 'src/sources/gog_metadata.dart';
export 'src/title_key.dart';
export 'src/unreachable.dart';
export 'src/workers/base.dart';
export 'src/workers/resolver.dart';
export 'src/workers/vision.dart';
