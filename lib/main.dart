import 'dart:async';

import 'package:campus_mobile_experimental/app_constants.dart';
import 'package:campus_mobile_experimental/app_provider.dart';
import 'package:campus_mobile_experimental/app_router.dart'
    as campusMobileRouter;
import 'package:campus_mobile_experimental/app_styles.dart';
import 'package:campus_mobile_experimental/core/models/authentication.dart';
import 'package:campus_mobile_experimental/core/models/user_profile.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

bool showOnboardingScreen = true;
bool isFirstRunFlag = false;
bool executedInitialDeeplinkQuery = false;

void main() async
{
  /// Record zoned errors - https://firebase.flutter.dev/docs/crashlytics/usage#zoned-errors
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    final mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      WidgetsFlutterBinding.ensureInitialized();
      await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    }

    // dotenv loading
    await dotenv.load(isOptional: true);

    /// Enable crash analytics - https://firebase.flutter.dev/docs/crashlytics/usage#toggle-crashlytics-collection
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    /// Record uncaught errors - https://firebase.flutter.dev/docs/crashlytics/usage#handling-uncaught-errors
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    await initializeHive();
    await initializeApp();
    runApp(CampusMobile());
  }, (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack));
}

Future<void> initializeHive() async {
  await Hive.initFlutter('.');
  Hive.registerAdapter(AuthenticationModelAdapter());
  Hive.registerAdapter(UserProfileModelAdapter());
}

Future<void> initializeApp() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('first_run') ?? true) {
    await clearSecuredStorage();
    await clearHiveStorage();
    prefs.setBool('showOnboardingScreen', true);
    prefs.setBool('first_run', false);
  }

  showOnboardingScreen = prefs.getBool('showOnboardingScreen') ?? true;
}

Future<void> clearSecuredStorage() async {
  FlutterSecureStorage storage = FlutterSecureStorage();
  await storage.deleteAll();
}

Future<void> clearHiveStorage() async {
  await (await Hive.openBox(DataPersistence.cardStates)).deleteFromDisk();
  await (await Hive.openBox(DataPersistence.cardOrder)).deleteFromDisk();
  await (await Hive.openBox(DataPersistence.AuthenticationModel))
      .deleteFromDisk();
  await (await Hive.openBox(DataPersistence.UserProfileModel)).deleteFromDisk();
}

class CampusMobile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = ThemeData(
      useMaterial3: false,
      primaryColor: lightPrimaryColor,
      textTheme: lightThemeText,
      iconTheme: lightIconTheme,
      appBarTheme: lightAppBarTheme,
      listTileTheme: lightListTileTheme,
      colorScheme:
        ColorScheme.fromSwatch(primarySwatch: ColorPrimary)
          .copyWith(
            background: lightButtonColor,
            brightness: Brightness.light, // added
          ),
    );

    final ThemeData darkTheme = ThemeData(
      useMaterial3: false,
      primaryColor: darkPrimaryColor,
      textTheme: darkThemeText,
      iconTheme: darkIconTheme,
      appBarTheme: darkAppBarTheme,
      unselectedWidgetColor: darkAccentColor,
      listTileTheme: darkListTileTheme,
      colorScheme:
        ColorScheme.fromSwatch(primarySwatch: ColorPrimary)
          .copyWith(
            background: darkButtonColor,
            brightness: Brightness.dark, // added
          ),
    );

    return MultiProvider(
      providers: providers,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: true,
        title: 'UC San Diego',
        theme: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(secondary: darkAccentColor),
        ),
        darkTheme: darkTheme.copyWith(
          colorScheme:
              darkTheme.colorScheme.copyWith(secondary: lightAccentColor),
        ),
        initialRoute: showOnboardingScreen
            ? RoutePaths.OnboardingInitial
            : RoutePaths.BottomNavigationBar,
        onGenerateRoute: campusMobileRouter.Router.generateRoute,
        navigatorObservers: [
          observer,
        ],
      ),
    );
  }
}
