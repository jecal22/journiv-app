import 'dart:io';

import 'package:markdown/markdown.dart' as md;

import 'media_markdown_helper.dart';

const _highlightPattern = r'==(.+?)==';
const _underlinePattern = r'<u>(.+?)</u>';

/// Simplified Markdown to Delta converter for migration binary.
///
/// Converts markdown AST to Quill Delta JSON format without Flutter dependencies.
/// Reuses the same markdown parsing logic as the frontend for compatibility.
class MarkdownConverter {
  MarkdownConverter._();

  /// Converts Markdown string to Quill Delta JSON.
  ///
  /// Returns a Map representing the Delta JSON structure:
  /// ```json
  /// {
  ///   "ops": [
  ///     {"insert": "Bold", "attributes": {"bold": true}},
  ///     {"insert": " text\n"}
  ///   ]
  /// }
  /// ```
  static Map<String, dynamic> markdownToDeltaJson(String markdown) {
    // Strip media shortcodes - frontend will handle them
    final trimmedMarkdown = MediaMarkdownHelper.stripMediaShortcodes(markdown.trimRight());

    if (trimmedMarkdown.isEmpty) {
      return {
        'ops': [
          {'insert': '\n'}
        ]
      };
    }

    try {
      // Parse markdown with GitHub-flavored syntax
      final markdownDocument = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: [
          _HighlightSyntax(),
          _UnderlineSyntax(),
        ],
      );

      final ast = markdownDocument.parseLines(trimmedMarkdown.split('\n'));

      // Convert AST to Delta ops
      final ops = _convertNodesToOps(ast);

      // Ensure delta ends with newline
      if (ops.isEmpty || !(ops.last['insert'] as String).endsWith('\n')) {
        ops.add({'insert': '\n'});
      }

      return {'ops': ops};
    } catch (e, stackTrace) {
      // Fallback: return raw text
      stderr.writeln('Warning: Failed to convert markdown to delta: $e');
      stderr.writeln('Stack trace: $stackTrace');
      stderr.writeln('Returning raw text fallback');
      return {
        'ops': [
          {'insert': trimmedMarkdown},
          {'insert': '\n'}
        ]
      };
    }
  }

  /// Convert markdown AST nodes to Delta ops
  static List<Map<String, dynamic>> _convertNodesToOps(List<md.Node> nodes) {
    final ops = <Map<String, dynamic>>[];

    for (final node in nodes) {
      _processNode(node, ops, {});
    }

    return ops;
  }

  /// Process a single markdown node and add corresponding ops
  static void _processNode(
    md.Node node,
    List<Map<String, dynamic>> ops,
    Map<String, dynamic> currentAttributes,
  ) {
    if (node is md.Element) {
      final newAttributes = Map<String, dynamic>.from(currentAttributes);

      // Block-level elements
      switch (node.tag) {
        case 'h1':
          newAttributes['header'] = 1;
          break;
        case 'h2':
          newAttributes['header'] = 2;
          break;
        case 'h3':
          newAttributes['header'] = 3;
          break;
        case 'h4':
          newAttributes['header'] = 4;
          break;
        case 'h5':
          newAttributes['header'] = 5;
          break;
        case 'h6':
          newAttributes['header'] = 6;
          break;
        case 'blockquote':
          newAttributes['blockquote'] = true;
          break;
        case 'code':
          if (node.attributes['class']?.startsWith('language-') ?? false) {
            // Code block
            newAttributes['code-block'] = true;
          } else {
            // Inline code
            newAttributes['code'] = true;
          }
          break;
        case 'pre':
          newAttributes['code-block'] = true;
          break;
        case 'ul':
          // Unordered list - children will handle
          break;
        case 'ol':
          // Ordered list - children will handle
          break;
        case 'li':
          // List item - check parent for type
          final parent = node.attributes['parent'];
          if (parent == 'ul') {
            newAttributes['list'] = 'bullet';
          } else if (parent == 'ol') {
            newAttributes['list'] = 'ordered';
          }
          // Check for task list
          if (node.children?.first is md.Element) {
            final firstChild = node.children!.first as md.Element;
            if (firstChild.tag == 'input' && firstChild.attributes['type'] == 'checkbox') {
              newAttributes['list'] = 'checked';
              if (firstChild.attributes['checked'] == 'true') {
                newAttributes['checked'] = true;
              }
              // Skip the checkbox element
              node.children!.removeAt(0);
            }
          }
          break;

        // Inline elements
        case 'strong':
        case 'b':
          newAttributes['bold'] = true;
          break;
        case 'em':
        case 'i':
          newAttributes['italic'] = true;
          break;
        case 'u':
        case 'ins':
          newAttributes['underline'] = true;
          break;
        case 'mark':
          newAttributes['highlight'] = true;
          break;
        case 's':
        case 'del':
          newAttributes['strike'] = true;
          break;
        case 'a':
          newAttributes['link'] = node.attributes['href'];
          break;
        case 'img':
          // Handle images as embeds
          ops.add({
            'insert': {
              'image': node.attributes['src'],
            },
          });
          return;
        case 'br':
          ops.add({'insert': '\n', if (currentAttributes.isNotEmpty) 'attributes': currentAttributes});
          return;
        case 'p':
          // Paragraph - process children then add newline
          for (final child in node.children ?? <md.Node>[]) {
            _processNode(child, ops, newAttributes);
          }
          ops.add({'insert': '\n', if (newAttributes.isNotEmpty) 'attributes': newAttributes});
          return;
      }

      // Process children with updated attributes
      for (final child in node.children ?? <md.Node>[]) {
        _processNode(child, ops, newAttributes);
      }

      // Add newline for block elements
      if (_isBlockElement(node.tag)) {
        ops.add({'insert': '\n', if (newAttributes.isNotEmpty) 'attributes': newAttributes});
      }
    } else if (node is md.Text) {
      // Text node
      final text = node.text;
      if (text.isNotEmpty) {
        ops.add({
          'insert': text,
          if (currentAttributes.isNotEmpty) 'attributes': currentAttributes,
        });
      }
    }
  }

  static bool _isBlockElement(String tag) {
    return const [
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'pre',
      'ul',
      'ol',
      'li'
    ].contains(tag);
  }
}

/// Custom markdown syntax for ==highlight== text
class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax() : super(_highlightPattern, startCharacter: 0x3d /* '=' */);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[1];
    if (text == null || text.isEmpty) {
      return false;
    }
    parser.addNode(md.Element.text('mark', text));
    return true;
  }
}

/// Custom markdown syntax for <u>underline</u> text
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(_underlinePattern, startCharacter: 0x3c /* '<' */);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[1];
    if (text == null || text.isEmpty) {
      return false;
    }
    parser.addNode(md.Element.text('u', text));
    return true;
  }
}
