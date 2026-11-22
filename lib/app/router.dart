import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/session.dart';
import '../features/company/company_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/login/login_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/server_setup_screen.dart';
import 'providers.dart';

abstract final class Routes {
  static const company = '/company';
  static const customServer = '/company/custom';
  static const login = '/login';
  static const home = '/home';
  static const history = '/home/history';
  static const settings = '/home/settings';
}

/// Company (or custom server) → Login → Home. A 401, logout or "Change
/// company" moves back automatically.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen<Session>(sessionProvider, (previous, next) {
    if (previous?.isLoggedIn != next.isLoggedIn || previous?.hasServer != next.hasServer) {
      refresh.value++;
    }
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      if (!session.hasServer) return location.startsWith(Routes.company) ? null : Routes.company;
      if (!session.isLoggedIn) return location == Routes.login ? null : Routes.login;
      if (location.startsWith(Routes.company) || location == Routes.login) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.company,
        builder: (_, _) => const CompanyScreen(),
        routes: [GoRoute(path: 'custom', builder: (_, _) => const ServerSetupScreen())],
      ),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(path: 'history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
