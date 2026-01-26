import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'utils/markdown_converter.dart';

/// Journiv Markdown to Quill Delta Migration Tool
///
/// Converts markdown content to Quill Delta JSON format for database migration.
/// Designed to match the frontend conversion logic exactly for 100% compatibility.
///
/// Exit Codes:
///   0 - Success
///   1 - Invalid arguments
///   2 - Conversion error

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Show version information',
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: Invalid arguments - $e');
    stderr.writeln();
    _printUsage(parser);
    exit(1);
  }

  // Handle flags
  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  if (args['version'] as bool) {
    print('Journiv Markdown Migrator v1.0.0');
    print('Compatible with: markdown_quill 4.3.0, dart_quill_delta 10.8.3');
    exit(0);
  }

  // Validate input
  if (args.rest.isEmpty) {
    stderr.writeln('Error: Missing required markdown content argument');
    stderr.writeln();
    _printUsage(parser);
    exit(1);
  }

  final markdown = args.rest.first;

  // Handle empty content
  if (markdown.isEmpty) {
    // Return minimal valid Delta for empty content
    final emptyDelta = {'ops': [{'insert': '\n'}]};
    print(jsonEncode(emptyDelta));
    exit(0);
  }

  try {
    // Convert markdown to Delta JSON
    final deltaJson = MarkdownConverter.markdownToDeltaJson(markdown);

    // Output JSON to stdout (consumed by Python subprocess)
    print(jsonEncode(deltaJson));
    exit(0);
  } catch (e, stackTrace) {
    stderr.writeln('Error: Failed to convert markdown to Delta');
    stderr.writeln('Exception: $e');
    stderr.writeln('Stack trace: $stackTrace');
    stderr.writeln();
    stderr.writeln('Input markdown (first 500 chars):');
    stderr.writeln(markdown.substring(0, markdown.length > 500 ? 500 : markdown.length));
    exit(2);
  }
}

void _printUsage(ArgParser parser) {
  print('Journiv Markdown to Quill Delta Migration Tool');
  print('');
  print('Usage: migrator [options] "<markdown-content>"');
  print('');
  print('Converts markdown text to Quill Delta JSON format.');
  print('Output is written to stdout as JSON.');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  migrator "# Heading\\n\\n**Bold** text"');
  print('  migrator "Text with ==highlight=="');
  print('  migrator "- [ ] Todo item"');
  print('');
  print('Exit codes:');
  print('  0 - Success');
  print('  1 - Invalid arguments');
  print('  2 - Conversion error');
}
