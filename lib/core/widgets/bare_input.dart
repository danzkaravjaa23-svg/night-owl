import 'package:flutter/material.dart';

/// For fields that sit inside their own styled container (pill, card):
/// strips the theme's fill and every border so no second box is drawn.
InputDecoration bareInput({
  String? hintText,
  TextStyle? hintStyle,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(vertical: 12),
  bool hideCounter = false,
}) =>
    InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      filled: false,
      isDense: true,
      contentPadding: contentPadding,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      // maxLength-тэй талбарт тоолуурыг нуух
      counterText: hideCounter ? '' : null,
    );
