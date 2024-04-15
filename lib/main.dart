import 'package:flutter/material.dart';
import 'package:name_app/models/UserModel.dart';
import 'package:provider/provider.dart';
import 'login/LoginScreen.dart';
import 'widgets/ButtonWidget.dart';
import 'widgets/InterestInputForm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => UserModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const appTitle = 'Drawer Demo';

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: appTitle,
      home: MyHomePage(title: appTitle),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  
  bool _signedIn = false;
  String _name = '';
  String _uid = '';
  int _selectedIndex = 0;

  late List<Widget> _signedOutWidgetOptions;
  late List<Widget> _signedInWidgetOptions;
  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  @override
  void initState() {
    initializeFirebase();

    _signedOutWidgetOptions = <Widget>[
    Text(
      'Index 0: Replace this text widget with the google map widget',
      style: optionStyle,
    ),
    LoginScreen(
      signedIn : _signedIn,
      onSignInChanged : _handleSignInChanged,
      onSelectedIndexChanged: _onItemTapped,
      onNameChanged: _handleNameChanged,
      onUidChanged: _handleUidChanged,
    ),
  ];
    _signedInWidgetOptions = <Widget>[
      Text(
        'Index 0: Replace this text widget with the google map widget',
        style: optionStyle,
      ),
      InterestInputForm(),
      ButtonWidget(),
      Text(
        'Index 3: Replace this text widget with the Messages widget',
        style: optionStyle,
      ),
      Text(
        'Index 4: Replace this text widget with the Sign Out widget',
        style: optionStyle,
      ),
    ];
    super.initState();
  }

  void _handleSignInChanged(bool newValue) {
    setState(() {
      _signedIn = newValue;
    });
  }

  void _handleNameChanged(String newValue) {
    setState(() {
      _name = newValue;
    });
  }

  void _handleUidChanged(String newValue) {
    setState(() {
      _uid = newValue;
    });
    // this gets the global instance of usermodel and allows us to access methods
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeUid(newValue);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  static const TextStyle optionStyle =
      TextStyle(fontSize: 30, fontWeight: FontWeight.bold);


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _signedIn ? _signedInWidgetOptions[_selectedIndex] : _signedOutWidgetOptions[_selectedIndex],
      ),
      drawer: Drawer(
        // Add a ListView to the drawer. This ensures the user can scroll
        // through the options in the drawer if there isn't enough vertical
        // space to fit everything.
        child: _signedIn ? ListView(
          // Important: Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text("$_name : $_uid"),
            ),
            ListTile(
              title: const Text('Map'),
              selected: _selectedIndex == 0,
              onTap: () {
                // Update the state of the app
                _onItemTapped(0);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('My Interests'),
              selected: _selectedIndex == 1,
              onTap: () {
                // Update the state of the app
                _onItemTapped(1);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Account'),
              selected: _selectedIndex == 2,
              onTap: () {
                // Update the state of the app
                _onItemTapped(2);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Messages'),
              selected: _selectedIndex == 3,
              onTap: () {
                // Update the state of the app
                _onItemTapped(3);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Sign Out'),
              selected: _selectedIndex == 0,
              onTap: () {
                // Update the state of the app
                _onItemTapped(0);
                _handleSignInChanged(false);
                _handleNameChanged('');
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
          ],
        ) : ListView(
          // Important: Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text("$_name : $_uid"),
            ),
            ListTile(
              title: const Text('Map'),
              selected: _selectedIndex == 0,
              onTap: () {
                // Update the state of the app
                _onItemTapped(0);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Sign In'),
              selected: _selectedIndex == 1,
              onTap: () {
                // Update the state of the app
                _onItemTapped(1);
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}