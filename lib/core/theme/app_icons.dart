import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Night Owl icon set (DS-09). Use these instead of picking `Icons.*` per
/// screen, so one concept always has one glyph.
///
/// Rules:
/// * One family: Material **Rounded**.
/// * Inactive / unselected = the rounded family's OUTLINE glyph
///   (`*_border_rounded`, `*_outline_rounded`, `*_none_rounded`).
/// * Active / selected = the FILLED rounded glyph (`*_rounded`).
/// * Only when the rounded family has no outline glyph, fall back to the
///   `*_outlined` glyph (here: [comment], [shortVideo], [venue],
///   [imageBroken]).
/// * Type glyphs that carry no state ([venueType]) are filled rounded.
/// * Emoji are for user content only (messages, captions, stickers), never
///   for UI chrome, placeholders or venue types.
///
/// The dock follows the same rule: [venue]/[venueActive] (Газрууд),
/// [feed]/[feedActive] (Нийтлэл), [add] (create), [message]/[messageActive]
/// (Мессеж), [profile]/[profileActive] (Профайл).
abstract final class AppIcons {
  // ─── Navigation ───

  /// Back in app bars and headers (replaces arrow_back, arrow_back_ios_new,
  /// chevron_left and their variants).
  static const IconData back = Icons.chevron_left_rounded;

  /// Disclosure chevron at the end of a row that opens another page.
  static const IconData forward = Icons.chevron_right_rounded;

  /// Close a sheet, a dialog or a full-screen viewer.
  static const IconData close = Icons.close_rounded;

  static const IconData search = Icons.search_rounded;

  /// Overflow menu ("...") on posts, reels, profiles and threads.
  static const IconData more = Icons.more_horiz_rounded;

  /// Create (dock centre button, "+ нэмэх").
  static const IconData add = Icons.add_rounded;

  // ─── Social actions ───

  static const IconData like = Icons.favorite_border_rounded;
  static const IconData likeActive = Icons.favorite_rounded;

  static const IconData save = Icons.bookmark_border_rounded;
  static const IconData saveActive = Icons.bookmark_rounded;

  /// Comments (Сэтгэгдэл). Deliberately not the chat bubble: that glyph is
  /// [message], and the feed shows both on one screen.
  static const IconData comment = Icons.mode_comment_outlined;

  /// Filled form of [comment], for filled type badges (notifications).
  static const IconData commentActive = Icons.mode_comment_rounded;

  /// Share sheet: the Android share glyph, the iOS share glyph on Apple
  /// platforms (also in Safari on iPhone).
  static IconData get share => switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => Icons.ios_share_rounded,
        _ => Icons.share_rounded,
      };

  /// Send a typed message or comment (composer button). Not for sharing.
  static const IconData send = Icons.send_rounded;

  // ─── Destinations (inactive outline / active filled) ───

  /// "Богино видео" (reels): the one glyph for the concept, replacing the
  /// compass, clapper, play and video-library glyphs.
  static const IconData shortVideo = Icons.smart_display_outlined;
  static const IconData shortVideoActive = Icons.smart_display_rounded;

  /// Мессеж (DM inbox, dock tab, header shortcut).
  static const IconData message = Icons.chat_bubble_outline_rounded;
  static const IconData messageActive = Icons.chat_bubble_rounded;

  static const IconData notifications = Icons.notifications_none_rounded;
  static const IconData notificationsActive = Icons.notifications_rounded;

  /// Газар: a venue, its address row, the "Газрууд" dock tab.
  static const IconData venue = Icons.location_on_outlined;
  static const IconData venueActive = Icons.location_on_rounded;

  /// Нийтлэл (people feed) dock tab.
  static const IconData feed = Icons.people_outline_rounded;
  static const IconData feedActive = Icons.people_rounded;

  /// Профайл dock tab.
  static const IconData profile = Icons.person_outline_rounded;
  static const IconData profileActive = Icons.person_rounded;

  // ─── States ───

  /// Placeholder for an image or video that failed to load (replaces the
  /// 📸 emoji placeholders).
  static const IconData imageBroken = Icons.image_not_supported_outlined;

  /// Glyph for a venue type key as stored in `venue_type`. Covers every type
  /// key of `Venue.typeLabel` (lib/models/venue.dart), the map filter's
  /// `bars` group and the venue editor's types; it replaced the old venue
  /// type emoji. Unknown or missing types get the filled venue pin.
  static IconData venueType(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'bar' || 'bars' => Icons.local_bar_rounded,
        'pub' => Icons.sports_bar_rounded,
        'lounge' => Icons.wine_bar_rounded,
        'rooftop' => Icons.location_city_rounded,
        'nightclub' => Icons.headphones_rounded,
        'karaoke' => Icons.mic_rounded,
        'jazz' => Icons.music_note_rounded,
        'restaurant' => Icons.restaurant_rounded,
        'cafe' => Icons.local_cafe_rounded,
        _ => venueActive,
      };
}
