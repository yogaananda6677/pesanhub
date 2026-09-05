import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/navigation/app_destination.dart';
import 'package:pesenhub_app/shell/app_shell.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('Issue #121 responsive redesign matrix', () {
    const viewports = <String, Size>{
      'compact-360': Size(360, 800),
      'mobile-390': Size(390, 844),
      'tablet-768': Size(768, 1024),
      'desktop-1280': Size(1280, 800),
    };

    for (final viewport in viewports.entries) {
      for (final scale in [1.0, 2.0]) {
        for (final destination in AppDestination.values) {
          testWidgets(
            '${viewport.key} at ${scale}x renders ${destination.name} without overflow',
            (tester) async {
              tester.view.physicalSize = viewport.value;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.lightTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: viewport.value,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: AppShell(initialIndex: destination.index),
                  ),
                ),
              );
              await tester.pump();
            },
          );
        }
      }
    }
  });
}
