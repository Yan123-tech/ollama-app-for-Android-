import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// ─── Inline Math: $...$ and \(...\) ──────────────────────────────

class InlineMathSyntax extends md.InlineSyntax {
  // Matches $...$ (not $$) OR \(...\)
  static const _pattern =
      r'\$(?!\$)((?:[^\$\n]|\\\$)+?)\$|\\\((.+?)\\\)';

  InlineMathSyntax() : super(_pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match[1] ?? match[2] ?? '';
    parser.addNode(md.Element.text('inlinemath', content));
    return true;
  }
}

// ─── Block Math: $$...$$ and \[...\] ─────────────────────────────

class BlockMathSyntax extends md.BlockSyntax {
  static final _dollarSingle = RegExp(r'^\$\$(.+)\$\$\s*$');
  static final _dollarEnd = RegExp(r'^\$\$\s*$');
  static final _bracketSingle = RegExp(r'^\\\[(.+)\\\]\s*$');
  static final _bracketEnd = RegExp(r'^\\\]\s*$');

  @override
  RegExp get pattern => RegExp(r'^(\$\$|\\\[)');

  @override
  bool canParse(md.BlockParser parser) =>
      pattern.hasMatch(parser.current.content);

  @override
  md.Node? parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final isDollar = firstLine.startsWith(r'$$');

    // Single-line variants: $$...$$ or \[...\]
    final single = isDollar
        ? _dollarSingle.firstMatch(firstLine)
        : _bracketSingle.firstMatch(firstLine);
    if (single != null) {
      parser.advance();
      return md.Element('blockmath', [md.Text(single[1]!.trim())]);
    }

    // Multi-line: collect until closing delimiter
    final remainder = firstLine.substring(2).trim();
    parser.advance();

    final buf = StringBuffer();
    if (remainder.isNotEmpty) buf.writeln(remainder);

    while (!parser.isDone) {
      final line = parser.current.content;
      final isEnd =
          isDollar ? _dollarEnd.hasMatch(line) : _bracketEnd.hasMatch(line);
      if (isEnd) {
        parser.advance();
        break;
      }
      buf.writeln(line);
      parser.advance();
    }

    return md.Element('blockmath', [md.Text(buf.toString().trim())]);
  }
}

// ─── Math Display Widget (no external package) ────────────────────

/// Displays LaTeX source in a visually distinct styled block.
/// Shows the raw LaTeX with monospace font and a "math" label.
Widget buildMathWidget(String tex, Color textColor, bool isBlock) {
  final bg = textColor.withOpacity(0.07);
  final border = textColor.withOpacity(0.22);

  if (isBlock) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label bar
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: border,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Text(
                'math',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: textColor.withOpacity(0.65),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // LaTeX source
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(
                tex,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  } else {
    // Inline math: small styled pill
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Text(
          tex,
          style: TextStyle(
            color: textColor,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─── Inline Math Builder ──────────────────────────────────────────

class InlineMathBuilder extends MarkdownElementBuilder {
  final Color textColor;
  InlineMathBuilder(this.textColor);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return buildMathWidget(element.textContent, textColor, false);
  }
}

// ─── Block Math Builder ───────────────────────────────────────────

class BlockMathBuilder extends MarkdownElementBuilder {
  final Color textColor;
  BlockMathBuilder(this.textColor);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return buildMathWidget(element.textContent, textColor, true);
  }
}

// ─── Syntax Highlighting Builder ──────────────────────────────────

class CodeHighlightBuilder extends MarkdownElementBuilder {
  /// true  → dark code background (assistant messages in light theme)
  /// false → light code background (user messages or dark theme)
  final bool darkBackground;

  CodeHighlightBuilder({required this.darkBackground});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final classAttr = element.attributes['class'] ?? '';
    // Inline code has no class attribute – return null to use stylesheet styling
    if (classAttr.isEmpty) return null;

    final language = _resolveLanguage(
      classAttr.startsWith('language-')
          ? classAttr.substring('language-'.length)
          : classAttr,
    );

    final theme = darkBackground ? atomOneDarkTheme : githubTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Language label bar
            if (language.isNotEmpty && language != 'plaintext')
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                color: darkBackground
                    ? const Color(0xFF21252B)
                    : const Color(0xFFE1E4E8),
                child: Text(
                  language,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: darkBackground ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              ),
            // Highlighted code
            HighlightView(
              element.textContent.trimRight(),
              language: language.isNotEmpty ? language : 'plaintext',
              theme: theme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _resolveLanguage(String lang) {
    if (lang.isEmpty) return 'plaintext';
    const aliases = <String, String>{
      'js': 'javascript',
      'ts': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'sh': 'bash',
      'zsh': 'bash',
      'yml': 'yaml',
      'md': 'markdown',
      'kt': 'kotlin',
      'rs': 'rust',
      'cs': 'csharp',
      'c++': 'cpp',
      'h': 'cpp',
      'hpp': 'cpp',
      'dart': 'dart',
    };
    return aliases[lang.toLowerCase()] ?? lang.toLowerCase();
  }
}
