import 'package:flutter_test/flutter_test.dart';
import 'package:jedtoolkit/main.dart';

void main() {
  testWidgets('app shows the Phone Info screen', (tester) async {
    await tester.pumpWidget(const JedToolKitApp());
    expect(find.text('Phone Info'), findsOneWidget);
  });
}