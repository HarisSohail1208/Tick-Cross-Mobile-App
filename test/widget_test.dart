import 'package:flutter_test/flutter_test.dart';
import 'package:tick_cross/main.dart';

void main() {
  testWidgets('starts with mode selection and opens the game screen', (
    tester,
  ) async {
    await tester.pumpWidget(const TickCrossApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose Game Mode'), findsOneWidget);
    expect(find.text('Single Player'), findsOneWidget);
    expect(find.text('Double Player'), findsOneWidget);

    await tester.tap(find.text('Double Player'));
    await tester.pumpAndSettle();

    expect(find.text('TICK CROSS'), findsOneWidget);
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Team 2'), findsOneWidget);
    expect(find.text('Team 1 Turn'), findsOneWidget);
    expect(find.text('New Match'), findsOneWidget);
  });
}
