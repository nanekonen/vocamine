import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vacamine/main.dart';

void main() {
  testWidgets('app starts on materials tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: GlossalyzeApp()));

    expect(find.text('教材'), findsWidgets);
    expect(find.text('単語帳'), findsOneWidget);
    expect(find.text('マイページ'), findsOneWidget);
  });
}
