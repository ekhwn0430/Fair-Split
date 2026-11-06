import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fair_split/main.dart';

void main() {
  testWidgets('GEMINI_API_KEY가 없으면 안내 화면을 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.textContaining('GEMINI_API_KEY'), findsOneWidget);
  });
}
