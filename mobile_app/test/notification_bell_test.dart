import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_mobile_app/app/theme.dart';
import 'package:hr_mobile_app/core/ui/widgets.dart';

void main() {
  Future<Size> bellSize(WidgetTester t, int count) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brand.fallback, Brightness.light, arabic: false),
      home: Scaffold(body: Center(child: NotificationBell(count: count, onTap: () {}))),
    ));
    return t.getSize(find.byType(NotificationBell));
  }

  testWidgets('bell keeps its 44x44 shape with and without notifications', (t) async {
    expect(await bellSize(t, 0), const Size(44, 44));
    expect(await bellSize(t, 3), const Size(44, 44));
    expect(await bellSize(t, 120), const Size(44, 44));
    expect(find.text('9+'), findsOneWidget);
  });
}
