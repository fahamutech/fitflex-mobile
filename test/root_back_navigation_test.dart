import 'package:fitflexmobile/shared/root_back_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'root back exits to Android launcher instead of revealing a black route',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });

      handleRootBack(didPop: false);
      await Future<void>.delayed(Duration.zero);

      expect(calls.map((call) => call.method), contains('SystemNavigator.pop'));
    },
  );

  test(
    'back already handled by a nested route does not exit the app',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });

      handleRootBack(didPop: true);
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    },
  );
}
