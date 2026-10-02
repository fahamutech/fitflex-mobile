import 'package:flutter/material.dart';

/// A push that arrives while the app is open is not shown by the phone —
/// Android only puts a notification in the tray for an app in the
/// background. So the app shows it itself: a banner with the title and
/// text, and a button that opens the message.
void showPushBanner(
  ScaffoldMessengerState messenger, {
  required String? title,
  required String? body,
  required String openLabel,
  required VoidCallback onOpen,
}) {
  final heading = (title ?? '').trim();
  final text = (body ?? '').trim();
  if (heading.isEmpty && text.isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('push-banner'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading.isNotEmpty)
              Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (text.isNotEmpty)
              Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        action: SnackBarAction(label: openLabel, onPressed: onOpen),
      ),
    );
}
