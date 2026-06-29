import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/utility/BackendIntegration.dart';
import 'package:intrst/widgets/Account.dart';
import 'package:intrst/widgets/IncomingFriendRequests.dart';
import 'package:intrst/widgets/Interests/Interests.dart';
//import 'package:intrst/widgets/Interests.dart';
import 'package:intrst/widgets/Messaging.dart';
import 'package:intrst/widgets/FollowingFeed.dart';
import 'package:intrst/widgets/Preview.dart' as custom_preview;
import 'package:provider/provider.dart';
import 'legal_pages.dart';
import 'login/LoginScreen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:location/location.dart';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
//import 'package:flutter/rendering.dart';

//import is for google maps
import 'package:google_maps_flutter/google_maps_flutter.dart';

part 'main/home_state.dart';
part 'main/home_user_logic.dart';
part 'main/home_map_logic.dart';
part 'main/home_location_logic.dart';
part 'main/home_ui_logic.dart';
part 'main/home_notification_logic.dart';

Future<void> main() async {
  //debugPaintSizeEnabled = false;
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
      //name: 'web-intrst',
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(
    ChangeNotifierProvider<UserModel>.value(
      value: UserModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const appTitle = 'intrst';
  @override
  Widget build(BuildContext context) {
    final path = Uri.base.path;

    // Web deep-link routing
    if (path == '/support' || path == '/support/') {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SupportPage(),
      );
    }
    if (path == '/terms' || path == '/terms/') {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TermsOfServicePage(),
      );
    }
    if (path == '/privacy' || path == '/privacy/') {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PrivacyPolicyPage(),
      );
    }

    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      title: appTitle,
      home: const MyHomePage(title: appTitle),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
