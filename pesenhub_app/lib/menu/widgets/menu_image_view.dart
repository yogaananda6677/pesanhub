import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/menu_item.dart';

class MenuImageView extends StatelessWidget {
  final MenuItem item;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool allowNetworkFallback;

  const MenuImageView({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.allowNetworkFallback = false,
  });

  @override
  Widget build(BuildContext context) {
    final localPath = item.localImagePath;
    if (localPath != null && localPath.isNotEmpty) {
      return Image.file(
        File(localPath),
        key: ValueKey('cached-menu-image-${item.id}-$localPath'),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    final imageUrl = item.imageUrl;
    if (allowNetworkFallback && imageUrl != null) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: width,
    height: height,
    color: AppColors.surfaceVariant,
    alignment: Alignment.center,
    child: const Icon(
      Icons.restaurant_menu_rounded,
      color: AppColors.textMuted,
    ),
  );
}
