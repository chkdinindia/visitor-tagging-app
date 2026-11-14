import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'services/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final state = AppState();
  await state.init();

  runApp(ChangeNotifierProvider<AppState>.value(value: state, child: const VisitorTaggingApp()));
}

class VisitorTaggingApp extends StatefulWidget {
  const VisitorTaggingApp({super.key});

  @override
  State<VisitorTaggingApp> createState() => _VisitorTaggingAppState();
}

class _VisitorTaggingAppState extends State<VisitorTaggingApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.select<AppState, bool>((s) => s.isLoggedIn);
    return MaterialApp(
      title: 'Visitor Tagging',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: loggedIn
            ? const ScanScreen(key: ValueKey<String>('scan'))
            : const LoginScreen(key: ValueKey<String>('login')),
      ),
    );
  }
}
