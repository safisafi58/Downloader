import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_downloader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Video Downloader home screen loads', (tester) async {
    await tester.pumpWidget(const VideoDownloaderApp());
    await tester.pumpAndSettle();

    expect(find.text('Save videos with ease'), findsOneWidget);
    expect(find.text('Paste video link'), findsOneWidget);
  });
}
