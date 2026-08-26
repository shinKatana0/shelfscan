/// Nothing read the translated prose, so a word from the wrong language
/// shipped silently (T-0375).
///
/// T-0370's worker drafted `README.ja.md`'s summary bullet from the Russian
/// one and left a Russian word standing inside the Japanese sentence. It
/// caught that by eye and then said the thing that made this a task: nothing
/// else in the process would have. Everything the suite knew about the
/// translations was structural -- `guide_transcript_test.dart` pins their code
/// blocks byte for byte against the English, which enforces the rule that code
/// and program output are never translated. No check read a sentence, and a
/// reviewer who does not read the language sees a plausible-looking line.
///
/// ## The rule, and why it is not "this script may not appear"
///
/// A naive version is red at once. The translations quote English constantly
/// -- command names, paths, task ids, the invented fixture family, the
/// TRANSLATED-FROM line -- and Japanese prose carries Latin words as prose,
/// not as quotation. So the rule is **a script may not appear where another
/// script is the prose**, and it is made precise in two halves.
///
/// *Half one: what the prose of a document is.* Everything except the four
/// things blanked in [_prose] -- a fenced block, an indented block, a
/// backticked span, and a link's destination. The first two are code or
/// program output, which this project never translates. The third is the same
/// thing inline, and it is load-bearing rather than theoretical: `README.md`
/// and `README.ja.md` both quote a **Russian** compiler message inside one,
/// because that is what a Russian install of MSVC actually prints. The fourth
/// is a path or an anchor; the link's *text* is prose and stays.
///
/// An HTML comment is deliberately **not** blanked. It renders as nothing, but
/// it is written in the same sitting as the text under it -- the translation
/// headers are exactly the kind of thing drafted from the other language's
/// file -- so it is held to the same rule as the page.
///
/// *Half two: what may stand in that prose.* Each document declares the script
/// it is written in, and every character of its prose must be that script, or
/// Latin, or punctuation. Latin is allowed everywhere for the reason above.
/// Anything else -- Greek, Hangul, an emoji -- is allowed nowhere, so a script
/// nobody thought to name is caught as well as the two that prompted this.
///
/// One exemption, and it is the only one: the language switcher at the top of
/// every page, where each language's own name appears in the other two
/// languages' documents. Only the three names, only on a line matching
/// [_switcher], and the shape is pinned -- a nav line that grows a fourth
/// language fails here rather than quietly widening the hole. A test asserts
/// that without the exemption every one of the six navs *would* be reported,
/// so the exemption cannot outlive the scan that needs it.
///
/// ## What this cannot catch
///
/// A guard whose limits are unwritten gets trusted past them, so:
///
/// - **A wrong word in the right script.** An English word left in Japanese
///   prose, a Ukrainian or Bulgarian word in the Russian, a Chinese phrase
///   whose characters are all also kanji. Script is the only property judged
///   here, and it is the coarsest one.
/// - **A paragraph pasted from the wrong source file in the right script** --
///   the second failure the task names. Two Russian paragraphs are both
///   Cyrillic whichever section they belong to.
/// - **A translated line contradicting its own `STALE` header**, or the
///   English it claims to translate. Nothing here reads meaning, dates,
///   figures or commit ids.
/// - **Anything inside what half one blanks.** A Cyrillic word smuggled into
///   the Japanese file inside backticks passes, on purpose -- that is where
///   the localised compiler message legitimately lives.
/// - **The three language names on the switcher line.**
/// - **A paragraph after an unclosed backtick.** A span is closed by a blank
///   line, so an unbalanced backtick blinds the rest of its paragraph and no
///   more. That bound is asserted below rather than assumed.
///
/// The failure message names the offending character by codepoint and never
/// prints it. The console these suites are read from is not UTF-8, and a
/// message that cannot survive being displayed is a message nobody reads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// What a character is, coarsely. A language cannot be judged one character at
/// a time; a script can, and that is the whole of what this file claims.
enum _Script {
  /// Digits, spaces, and every punctuation mark and symbol the six documents
  /// use. Allowed everywhere.
  neutral,

  /// The Latin alphabet, accented forms included. Allowed everywhere: see the
  /// rule above.
  latin,

  cyrillic,

  /// Han, kana, and the punctuation and full-width forms Japanese sets its
  /// sentences with. The punctuation is in on purpose -- a fragment pasted out
  /// of the Japanese file may arrive carrying no kana at all.
  cjk,

  /// Everything else, allowed nowhere.
  other,
}

String _named(_Script script) => switch (script) {
      _Script.neutral => 'punctuation',
      _Script.latin => 'Latin',
      _Script.cyrillic => 'Cyrillic',
      _Script.cjk => 'CJK',
      _Script.other => 'a script this file does not name',
    };

_Script _scriptOf(int rune) {
  if (rune < 0x80) {
    final letter = (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A);
    return letter ? _Script.latin : _Script.neutral;
  }
  // The punctuation blocks rather than the marks themselves, so that a new
  // dash, quote or arrow in a document is not reported as a foreign script.
  if (rune >= 0xA0 && rune <= 0xBF) return _Script.neutral;
  if (rune == 0xD7 || rune == 0xF7) return _Script.neutral;
  if (rune >= 0x2000 && rune <= 0x206F) return _Script.neutral;
  if (rune >= 0x2190 && rune <= 0x21FF) return _Script.neutral;
  if (rune >= 0x2700 && rune <= 0x27BF) return _Script.neutral;
  if (rune >= 0xC0 && rune <= 0x24F) return _Script.latin;
  if (rune >= 0x1E00 && rune <= 0x1EFF) return _Script.latin;
  if (rune >= 0x400 && rune <= 0x52F) return _Script.cyrillic;
  if (rune >= 0x2E80 && rune <= 0x2EFF) return _Script.cjk;
  if (rune >= 0x3000 && rune <= 0x30FF) return _Script.cjk;
  if (rune >= 0x3190 && rune <= 0x33FF) return _Script.cjk;
  if (rune >= 0x3400 && rune <= 0x4DBF) return _Script.cjk;
  if (rune >= 0x4E00 && rune <= 0x9FFF) return _Script.cjk;
  if (rune >= 0xF900 && rune <= 0xFAFF) return _Script.cjk;
  if (rune >= 0xFE30 && rune <= 0xFE4F) return _Script.cjk;
  if (rune >= 0xFF00 && rune <= 0xFFEF) return _Script.cjk;
  return _Script.other;
}

/// A published document and the script its sentences are written in.
class _Doc {
  const _Doc(this.path, this.prose);

  final String path;
  final _Script prose;

  bool allows(_Script script) =>
      script == _Script.neutral || script == _Script.latin || script == prose;
}

/// The six published documents. The four translations are the subject; the two
/// English originals are here because the same rule answers for them, and
/// because a stray line pasted the other way is the same defect.
const _documents = <_Doc>[
  _Doc('README.md', _Script.latin),
  _Doc('README.ru.md', _Script.cyrillic),
  _Doc('README.ja.md', _Script.cjk),
  _Doc('doc/guide.md', _Script.latin),
  _Doc('doc/guide.ru.md', _Script.cyrillic),
  _Doc('doc/guide.ja.md', _Script.cjk),
];

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();

List<String> _linesOf(String document) => const LineSplitter()
    .convert(File('${_repoRoot.path}/$document').readAsStringSync());

// ---------------------------------------------------------------------------
// The language switcher, the one exemption

const _languages = ['English', 'Русский', '日本語'];

/// Linked, or bold for the page you are already on.
String _navItem(String name) =>
    '(?:${RegExp.escape('**$name**')}|${RegExp.escape('[$name]')}'
    r'\([^)]+\))';

/// The exact shape of the nav line, in the exact order the six documents use.
/// Anything else -- a fourth language, a reordering, a different separator --
/// stops matching, and the census test below then fails rather than the
/// exemption silently covering a line nobody checked.
final _switcher = RegExp('^${_languages.map(_navItem).join(' · ')}\$');

/// Only the three names, and only on the switcher line.
String _withoutLanguageNames(String line) {
  var out = line;
  for (final name in _languages) {
    out = out.replaceAll(name, ' ' * name.length);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The prose of a document

class _ProseLine {
  const _ProseLine(this.number, this.text);

  final int number;
  final String text;
}

final _fence = RegExp(r'^(`{3,}|~{3,})');

/// Exactly four spaces then text. Five or more is a list item's continuation,
/// which Markdown renders as prose -- both guides carry Japanese and Russian
/// sentences that way, and blanking them would be a hole rather than a rule.
/// This is the same distinction `guide_transcript_test.dart` draws.
bool _opensIndented(String raw) =>
    raw.length > 4 && raw.startsWith('    ') && raw[4] != ' ';

/// Blanks backticked spans, keeping every other character where it was so a
/// failure can name a column.
///
/// A span may wrap across a line -- `doc/guide.md` has two that do -- so the
/// state is carried between lines. It is dropped at a blank line, which ends
/// the paragraph and with it anything Markdown would have left open.
class _Spans {
  int _open = 0;

  void reset() => _open = 0;

  String mask(String raw) {
    final units = raw.codeUnits.toList();
    var i = 0;
    while (i < units.length) {
      if (units[i] == 0x60) {
        var run = 0;
        while (i + run < units.length && units[i + run] == 0x60) {
          run++;
        }
        if (_open == 0) {
          _open = run;
        } else if (_open == run) {
          _open = 0;
        }
        for (var k = 0; k < run; k++) {
          units[i + k] = 0x20;
        }
        i += run;
        continue;
      }
      if (_open > 0) units[i] = 0x20;
      i++;
    }
    return String.fromCharCodes(units);
  }
}

final _destination = RegExp(r'\]\([^)]*\)');

String _withoutDestinations(String line) => line.replaceAllMapped(
    _destination, (m) => ']${' ' * (m.group(0)!.length - 1)}');

/// [lines] with everything that is not a sentence blanked out.
List<_ProseLine> _prose(List<String> lines) {
  final out = <_ProseLine>[];
  final spans = _Spans();
  var fence = '';
  var indented = false;
  var comment = false;

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();

    if (comment) {
      if (trimmed.contains('-->')) comment = false;
      out.add(_ProseLine(i + 1, spans.mask(raw)));
      continue;
    }
    if (fence.isNotEmpty) {
      if (trimmed.startsWith(fence)) fence = '';
      continue;
    }
    final opening = _fence.firstMatch(trimmed);
    if (opening != null) {
      fence = opening.group(1)!;
      indented = false;
      spans.reset();
      continue;
    }
    if (trimmed.startsWith('<!--')) {
      comment = !trimmed.contains('-->');
      indented = false;
      out.add(_ProseLine(i + 1, spans.mask(raw)));
      continue;
    }
    if (indented) {
      if (trimmed.isEmpty || raw.startsWith('    ')) continue;
      indented = false;
    } else if (_opensIndented(raw)) {
      indented = true;
      spans.reset();
      continue;
    }
    if (trimmed.isEmpty) spans.reset();
    if (_switcher.hasMatch(trimmed)) {
      out.add(_ProseLine(i + 1, _withoutLanguageNames(raw)));
      continue;
    }
    out.add(_ProseLine(i + 1, _withoutDestinations(spans.mask(raw))));
  }
  return out;
}

String _codepoint(int rune) =>
    'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// One line of [doc] per entry, naming the characters that do not belong.
List<String> _violations(_Doc doc, List<String> lines) {
  final found = <String>[];
  for (final line in _prose(lines)) {
    final wrong = <int>{};
    for (final rune in line.text.runes) {
      if (!doc.allows(_scriptOf(rune))) wrong.add(rune);
    }
    if (wrong.isEmpty) continue;
    found.add('${doc.path}:${line.number}: '
        '${_named(_scriptOf(wrong.first))} in prose written in '
        '${_named(doc.prose)} -- '
        '${wrong.take(8).map(_codepoint).join(' ')}'
        '${wrong.length > 8 ? ' and ${wrong.length - 8} more' : ''}');
  }
  return found;
}

// ---------------------------------------------------------------------------

void main() {
  group('a document is written in the script it says it is', () {
    for (final doc in _documents) {
      test(doc.path, () {
        final found = _violations(doc, _linesOf(doc.path));
        expect(found, isEmpty,
            reason: 'a character of a script this document does not write in '
                'is standing in one of its sentences. Each line is named with '
                'the codepoints, which the header explains. If it belongs -- a '
                'program message that really is localised, say -- it belongs '
                'inside backticks, where this scan does not look:\n'
                '${found.join('\n')}');
      });
    }
  });

  group('the scan can see what it claims to scan', () {
    // Half of every check in this project that reported nothing was a check
    // that could see nothing (`doc/conventions.md` 4a). Blanking is what this
    // file does most of, so a blanking bug would report a confident zero on
    // all six documents at once. The floor is deliberately far below what any
    // of them carries: it answers "did the prose survive", not "how much".
    for (final doc in _documents) {
      test('${doc.path} still has its own script left after the blanking', () {
        var own = 0;
        for (final line in _prose(_linesOf(doc.path))) {
          for (final rune in line.text.runes) {
            if (_scriptOf(rune) == doc.prose) own++;
          }
        }
        expect(own, greaterThan(500),
            reason: 'the blanking in `_prose` ate this document. Every check '
                'below it would pass on nothing.');
      });
    }
  });

  group('the language switcher, the one exemption', () {
    for (final doc in _documents) {
      test('${doc.path} carries exactly one', () {
        final nav = [
          for (final line in _linesOf(doc.path))
            if (_switcher.hasMatch(line.trim())) line.trim(),
        ];
        expect(nav, hasLength(1),
            reason: 'the exemption is written for one line of one shape. '
                'A nav line that changed shape is not exempt any more, and a '
                'second line that matches is not a nav line.');
        expect('**'.allMatches(nav.single).length, 2,
            reason: 'exactly one of the three names is the page you are on');
      });
    }

    test('and the scan would report every one of them without it', () {
      // An exemption for something the scan would not have reported anyway is
      // an exemption that has quietly stopped being needed -- and it would
      // still be believed. Breaking the separator is enough to take the line
      // out of `_switcher` and put it back into ordinary prose.
      for (final doc in _documents) {
        final nav = _linesOf(doc.path)
            .firstWhere((line) => _switcher.hasMatch(line.trim()));
        expect(_violations(doc, [nav.replaceAll('·', '-')]), isNotEmpty,
            reason: '${doc.path}: unexempted, its nav line is clean. Either '
                'the nav no longer names the other languages, or the scan '
                'stopped seeing them.');
      }
    });
  });

  group('what counts as prose', () {
    // Invented, and ordinary vocabulary in both languages: the Russian is the
    // word "word", the Japanese is "character".
    const russian = 'слово';
    const japanese = '文字';

    List<String> hits(_Script prose, String markdown) =>
        _violations(_Doc('fixture.md', prose),
            const LineSplitter().convert(markdown));

    test('a wrong-script word in a sentence is found, in each direction', () {
      expect(hits(_Script.cjk, 'これは $russian です。'), isNotEmpty);
      expect(hits(_Script.cyrillic, 'Это $japanese здесь.'), isNotEmpty);
      expect(hits(_Script.latin, 'A sentence with $russian in it.'),
          isNotEmpty);
      expect(hits(_Script.latin, 'A sentence with $japanese in it.'),
          isNotEmpty);
    });

    test('the same word in a fenced block is not', () {
      expect(hits(_Script.cjk, '```\n$russian\n```'), isEmpty);
      expect(hits(_Script.cyrillic, '```json\n"$japanese"\n```'), isEmpty);
    });

    test('the same word in an indented block is not', () {
      expect(hits(_Script.cjk, 'text\n\n    $russian\n\nmore text'), isEmpty);
    });

    test('a list continuation is prose, however deep it is indented', () {
      expect(hits(_Script.cjk, '- item\n     $russian\n'), isNotEmpty);
    });

    test('the same word in a code span is not, wrapped or not', () {
      expect(hits(_Script.cjk, 'これは `$russian` です。'), isEmpty);
      expect(hits(_Script.cjk, 'これは `one\n$russian` です。'), isEmpty);
      expect(hits(_Script.cjk, 'これは ``a `b` $russian`` です。'), isEmpty);
    });

    test('a link destination is not prose and its text is', () {
      expect(hits(_Script.cjk, '[text](./$russian.md) を見よ。'), isEmpty);
      expect(hits(_Script.cjk, '[$russian](./x.md) を見よ。'), isNotEmpty);
    });

    test('Latin is prose in all three, and is never reported', () {
      expect(hits(_Script.cjk, 'Windows で `scan-installs` を実行する。'),
          isEmpty);
      expect(hits(_Script.cyrillic, 'Запустите `scan` на Windows.'), isEmpty);
      expect(hits(_Script.latin, 'Run `scan` on Windows -- 3064 × 4080.'),
          isEmpty);
    });

    test('a script this file does not name is reported everywhere', () {
      expect(hits(_Script.latin, 'A sentence with αβ in it.'), isNotEmpty);
      expect(hits(_Script.cjk, '한국어 は日本語ではありません。'), isNotEmpty);
      expect(hits(_Script.cyrillic, 'Тут стоит 한국어.'), isNotEmpty);
    });

    test('an HTML comment is held to the same rule as the page', () {
      expect(hits(_Script.cjk, '<!-- a note with $russian in it -->'),
          isNotEmpty);
      expect(hits(_Script.cjk, '<!-- a note\n     with $russian -->'),
          isNotEmpty);
    });

    test('an unclosed span blinds its own paragraph and no more', () {
      expect(hits(_Script.cjk, 'これは `one です。\n\n$russian が残る。'),
          isNotEmpty);
    });
  });
}
