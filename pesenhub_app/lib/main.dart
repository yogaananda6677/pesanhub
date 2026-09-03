import 'package:flutter/material.dart';
import 'showcase/design_system_showcase.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PesenHubApp());
}

/// PesenHubApp is the root Flutter application widget for PesenHub POS/KDS.
class PesenHubApp extends StatelessWidget {
  const PesenHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PesenHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const DesignSystemShowcase(),
    );
  }
}
