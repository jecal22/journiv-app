/// Simplified media markdown helper for migration binary.
/// Only includes media shortcode stripping - no expansion needed for migration.
class MediaMarkdownHelper {
  MediaMarkdownHelper._();

  /// UUID v4 pattern matching standard format
  static const _mediaIdPattern =
      r'([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})';

  /// Matches media shortcodes: `![[media:uuid]]`
  static final RegExp _shortcodePattern = RegExp(
    '!\\[\\[media:$_mediaIdPattern\\]\\]',
    caseSensitive: false,
  );

  /// Strip media shortcodes when converting to Delta.
  ///
  /// During migration, media shortcodes are preserved in the markdown source.
  /// They'll be expanded by the frontend when loading the entry for display.
  /// For now, we just remove them from the Delta to prevent rendering issues.
  static String stripMediaShortcodes(String markdown) {
    if (!_shortcodePattern.hasMatch(markdown)) return markdown;
    return markdown.replaceAll(_shortcodePattern, '');
  }
}
