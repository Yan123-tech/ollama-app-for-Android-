import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

// ─── Cached Extension Set ────────────────────────────────────────────
// Built once and reused across all message rebuilds.

md.ExtensionSet? _cachedMathExtensionSet;

md.ExtensionSet get mathExtensionSet {
  return _cachedMathExtensionSet ??= md.ExtensionSet(
    [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, BlockMathSyntax()],
    <md.InlineSyntax>[
      md.EmojiSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      InlineMathSyntax(),
    ],
  );
}

// ─── Inline Math: $...$ and \(...\) ──────────────────────────────────
// Renders as inline code (monospace) — WebView can't be embedded inline.

class InlineMathSyntax extends md.InlineSyntax {
  static const _pattern =
      r'\$(?!\$)((?:[^\$\n]|\\\$)+?)\$|\\\((.+?)\\\)';

  InlineMathSyntax() : super(_pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match[1] ?? match[2] ?? '';
    parser.addNode(md.Element('code', [md.Text(content)]));
    return true;
  }
}

// ─── Block Math: $$...$$ and \[...\] ─────────────────────────────────

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

    final single = isDollar
        ? _dollarSingle.firstMatch(firstLine)
        : _bracketSingle.firstMatch(firstLine);
    if (single != null) {
      parser.advance();
      return md.Element('blockmath', [md.Text(single[1]!.trim())]);
    }

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

// ─── Block Math Builder ───────────────────────────────────────────────

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
    final latex = element.textContent;
    try {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: MathWebView(latex: latex, textColor: textColor),
      );
    } catch (_) {
      return _monoFallback(latex);
    }
  }

  Widget _monoFallback(String latex) {
    final bg = textColor.withOpacity(0.07);
    final border = textColor.withOpacity(0.22);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            latex,
            style: TextStyle(
              color: textColor,
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── KaTeX WebView Widget ─────────────────────────────────────────────

class MathWebView extends StatefulWidget {
  final String latex;
  final Color textColor;

  const MathWebView({
    super.key,
    required this.latex,
    required this.textColor,
  });

  @override
  State<MathWebView> createState() => _MathWebViewState();
}

class _MathWebViewState extends State<MathWebView> {
  WebViewController? _controller;
  double _height = 72.0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      final isDark = widget.textColor.computeLuminance() > 0.5;
      final fgColor = isDark ? '#e8e8e8' : '#212121';
      final latexJson = jsonEncode(widget.latex);

      final html = '''<!DOCTYPE html>
<html><head>
  <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{background:transparent;overflow:hidden}
    #math{color:$fgColor;padding:10px 8px;overflow-x:auto;font-size:15px;text-align:center}
    .katex-display{margin:0;overflow-x:auto;overflow-y:hidden}
    .katex-error{color:#e74c3c;font-size:12px;font-family:monospace}
  </style>
</head><body>
  <div id="math"></div>
  <script>
    var reported=false;
    function reportSize(){
      if(!reported){reported=true;SizeReporter.postMessage(String(document.body.scrollHeight||60));}
    }
    document.addEventListener("DOMContentLoaded",function(){
      var el=document.getElementById("math");
      var latex=$latexJson;
      if(typeof katex!=="undefined"){
        try{katex.render(latex,el,{displayMode:true,throwOnError:false});}
        catch(e){el.innerText=latex;}
      } else {
        el.innerText=latex;
      }
      document.fonts.ready.then(reportSize);
      setTimeout(reportSize,4000);
    });
  </script>
</body></html>''';

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'SizeReporter',
          onMessageReceived: (msg) {
            final h = double.tryParse(msg.message);
            if (h != null && mounted) {
              setState(() => _height = h.clamp(40.0, 500.0));
            }
          },
        )
        ..loadHtmlString(html);
    } catch (_) {
      _failed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _controller == null) {
      return _monoFallback();
    }
    return SizedBox(
      width: double.infinity,
      height: _height,
      child: WebViewWidget(controller: _controller!),
    );
  }

  Widget _monoFallback() {
    final bg = widget.textColor.withOpacity(0.07);
    final border = widget.textColor.withOpacity(0.22);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          widget.latex,
          style: TextStyle(
            color: widget.textColor,
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Syntax Highlighting Builder ──────────────────────────────────────

class CodeHighlightBuilder extends MarkdownElementBuilder {
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
    if (classAttr.isEmpty) return null;

    final language = _resolveLanguage(
      classAttr.startsWith('language-')
          ? classAttr.substring('language-'.length)
          : classAttr,
    );

    final code = element.textContent.trimRight();
    if (code.isEmpty) return null;

    final theme = darkBackground ? atomOneDarkTheme : githubTheme;

    try {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (language.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  color: darkBackground
                      ? const Color(0xFF21252B)
                      : const Color(0xFFE1E4E8),
                  child: Text(
                    language,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: darkBackground
                          ? Colors.grey[400]
                          : Colors.grey[700],
                    ),
                  ),
                ),
              HighlightView(
                code,
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
    } catch (_) {
      final bgColor = darkBackground
          ? const Color(0xFF282C34)
          : const Color(0xFFF6F8FA);
      final textColor = darkBackground ? Colors.white : Colors.black87;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: textColor,
              ),
            ),
          ),
        ),
      );
    }
  }

  static String _resolveLanguage(String lang) {
    if (lang.isEmpty) return '';
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
      'text': 'plaintext',
      'output': 'plaintext',
      'console': 'bash',
      'shell': 'bash',
      'terminal': 'bash',
    };
    return aliases[lang.toLowerCase()] ?? lang.toLowerCase();
  }
}
