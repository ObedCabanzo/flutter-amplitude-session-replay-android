import 'package:flutter/material.dart';
import 'package:flutter_application_3/analytics/amplitude_service.dart';
import 'package:flutter_application_3/analytics/braze_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AmplitudeService.instance.init(
    apiKeyAnalytics: 'api-key',
    apiKeySessionReplay: 'api-key',
    enableRemoteConfig: false
  );

  await BrazeService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;

  final _pages = const [HomeScreen(), SearchScreen(), SettingsScreen()];

  final _titles = const ['Home', 'Search', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_titles[_currentIndex]),
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton:
          _currentIndex == 0
              ? FloatingActionButton(
                onPressed: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('FAB en Home')));
                },
                tooltip: 'Action',
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}

/// ---------- Pantallas de prueba ----------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int counter = 0;

  @override
  void initState() {
    super.initState();
    AmplitudeService.instance.track("home_page_viewed");
    BrazeService.instance.logEvent("home_page_viewed");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Home Screen'),
          const SizedBox(height: 12),
          Text(
            'Counter: $counter',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed:
                () => setState(() {
                  counter++;
                  AmplitudeService.instance.track("count_updated");
                }),
            child: const Text('Increment Counter (solo Home)'),
          ),
        ],
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    AmplitudeService.instance.track("search_page_viewed");
    BrazeService.instance.logEvent("search_page_viewed");
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Search Screen'));
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  // use id state
  String userId = '';

  @override
  void initState() {
    super.initState();
    AmplitudeService.instance.track("settings_page_viewed");
    BrazeService.instance.logEvent("settings_page_viewed");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('Settings Screen'),
      // Add a Input component
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Set User ID',
              ),
              onChanged: (value) {
                // Set user ID locally
                userId = value;
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                AmplitudeService.instance.setUserId(userId);
                BrazeService.instance.setUserId(userId);
              },
              child: const Text('Set User ID'),
            ),
          ],
        ),
      ),

    ],),
    );
  }
}
