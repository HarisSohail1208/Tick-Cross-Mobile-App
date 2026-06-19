import 'package:flutter_test/flutter_test.dart';
import 'package:tick_cross/main.dart';

void main() {
  testWidgets('shows the Tick Cross game screen', (tester) async {
    await tester.pumpWidget(const TickCrossApp());

    expect(find.text('TICK CROSS'), findsOneWidget);
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Team 2'), findsOneWidget);
    expect(find.text('Team 1 Turn'), findsOneWidget);
    expect(find.text('New Match'), findsOneWidget);
  });
}
