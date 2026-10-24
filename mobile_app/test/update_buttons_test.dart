import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_mobile_app/app/theme.dart';

/// The app theme gives every button an infinite minimum width. Buttons placed in a Row must be
/// Expanded (as in the update dialog) or they fail to lay out and disappear.
void main() {
  testWidgets('update dialog buttons get a real size under the app theme', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brand.fallback, Brightness.light, arabic: false),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Row(children: [
              Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: () {}, child: const Text('Later'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: () {}, child: const Text('Update now'))),
            ]),
          ),
        ),
      ),
    ));
    expect(tester(t, 'Later').width, greaterThan(100));
    expect(tester(t, 'Update now').width, greaterThan(100));
    expect(t.takeException(), isNull);
  });
}

Size tester(WidgetTester t, String label) => t.getSize(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
