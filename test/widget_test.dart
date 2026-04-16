import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness pumps a bounded Material app smoke', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(child: Center(child: Text('OpenReef'))),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OpenReef'), findsOneWidget);
  });
}
