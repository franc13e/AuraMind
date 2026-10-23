// lib/main.dart — AuraMind standalone entry point
// Replace the existing lib/main.dart with this file.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'services/sensor_service.dart';
import 'screens/home_screen.dart';
import 'screens/trends_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/adoption_survey_screen.dart';
import 'auramind_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  runApp(const AuraMindApp());
}

class AuraMindApp extends StatelessWidget {
  const AuraMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SensorService()),
      ],
      child: MaterialApp(
        title: 'AuraMind',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const _AuraMindShell(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/settings':
              return MaterialPageRoute(builder: (_) => const SettingsScreen());
            case '/survey':
              return MaterialPageRoute(builder: (_) => const AdoptionSurveyScreen());
            default:
              return MaterialPageRoute(builder: (_) => const _AuraMindShell());
          }
        },
      ),
    );
  }
}

class _AuraMindShell extends StatefulWidget {
  const _AuraMindShell();
  @override
  State<_AuraMindShell> createState() => _AuraMindShellState();
}

class _AuraMindShellState extends State<_AuraMindShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    TrendsScreen(),
    AlertsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sensor = context.read<SensorService>();
      sensor.start();
      sensor.setPatientId('anonymous');
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<SensorService>().unreadAlerts;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'AuraMind',
          style: TextStyle(
            color: C.t1,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: C.t2, size: 20),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: C.surface,
          border: Border(top: BorderSide(color: C.border, width: 0.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  index: 0, current: _index,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home', badge: 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavItem(
                  index: 1, current: _index,
                  icon: Icons.show_chart_outlined,
                  activeIcon: Icons.show_chart,
                  label: 'Trends', badge: 0,
                  onTap: () => setState(() => _index = 1),
                ),
                _NavItem(
                  index: 2, current: _index,
                  icon: Icons.notifications_none,
                  activeIcon: Icons.notifications_rounded,
                  label: 'Alerts', badge: unread,
                  onTap: () => setState(() => _index = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index, current, badge;
  final IconData icon, activeIcon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.index, required this.current, required this.icon,
    required this.activeIcon, required this.label, required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(selected ? activeIcon : icon, key: ValueKey(selected),
                  size: 24, color: selected ? C.accent : C.t3),
            ),
            if (badge > 0)
              Positioned(
                top: -4, right: -6,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: C.danger, shape: BoxShape.circle),
                  child: Center(
                    child: Text('$badge',
                        style: const TextStyle(fontSize: 9, color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? C.accent : C.t3,
            ),
            child: Text(label),
          ),
        ]),
      ),
    );
  }
}