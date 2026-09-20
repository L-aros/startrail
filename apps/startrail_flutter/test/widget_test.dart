import 'package:flutter_test/flutter_test.dart';
import 'package:startrail/main.dart';

void main() {
  testWidgets('uses the formal Chinese brand and offline-first message', (
    tester,
  ) async {
    await tester.pumpWidget(const StarTrailApp());

    expect(find.text('拾星迹'), findsOneWidget);
    expect(find.text('默认离线保存，并在本机加密。'), findsOneWidget);
    expect(find.text('Flutter Demo'), findsNothing);
  });
}
