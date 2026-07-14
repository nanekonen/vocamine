import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vacamine/main.dart';
import 'package:vacamine/services/app_session.dart';

class _TestAppSessionNotifier extends AppSessionNotifier {
  @override
  AppSession build() => const AppSession(userId: 'guest');

  @override
  Future<void> load() async {}

  void completeLogin() {
    state = const AppSession(
      userId: 'test-user',
      isLoaded: true,
      setupCompleted: false,
    );
  }
}

void main() {
  testWidgets('session load replaces the startup spinner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith(_TestAppSessionNotifier.new),
        ],
        child: const GlossalyzeApp(),
      ),
    );

    expect(find.text('ログイン情報を読み込み中…'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlossalyzeApp)),
    );
    final notifier =
        container.read(appSessionProvider.notifier) as _TestAppSessionNotifier;
    notifier.completeLogin();
    await tester.pump();

    expect(find.text('ログイン情報を読み込み中…'), findsNothing);
    expect(find.text('現在の英語レベルを選択してください'), findsOneWidget);
  });
}
