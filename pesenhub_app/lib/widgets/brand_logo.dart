import 'package:flutter/material.dart';

/// Standard brand logo widget for Jenggirat Martabak & Terang Bulan.
class BrandLogo extends StatelessWidget {
  final double size;
  final BorderRadius? borderRadius;

  const BrandLogo({super.key, this.size = 32, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      'assets/images/logo_transparent.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Logo Jenggirat Martabak & Terang Bulan',
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
