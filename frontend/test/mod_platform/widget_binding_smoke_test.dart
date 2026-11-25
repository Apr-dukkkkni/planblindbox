import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Widget Binding Smoke Test', (tester) async {
    print('[SMOKE] Before pumpWidget');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('SMOKE TEST OK'),
        ),
      ),
    );

    print('[SMOKE] After pumpWidget');

    expect(find.text('SMOKE TEST OK'), findsOneWidget);
  });
}