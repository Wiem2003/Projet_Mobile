import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'controllers/user_session.dart';
import 'core/theme/app_theme.dart';
import 'models/auth/app_user.dart';
import 'models/auth/auth_model.dart';
import 'views/home_shell.dart';
import 'views/screens/auth_screens.dart';

/// Crée les modules d'un compte qui vient de se connecter.
typedef SessionFactory = UserSession Function(AppUser user);

/// Porte d'entrée : écran Sign in tant que personne n'est connecté, puis
/// l'application du compte connecté.
///
/// À chaque connexion, une [UserSession] fournit les Models et Controllers
/// du compte au-dessus de l'application (les écrans ouverts depuis l'accueil
/// y ont donc accès). À la déconnexion, elle est fermée et la navigation
/// repart de zéro.
class SmartPetApp extends StatefulWidget {
  const SmartPetApp({super.key, required this.sessionFactory, this.onSessionStarted});

  final SessionFactory sessionFactory;

  /// Appelé une fois les données du compte chargées (notification ouverte au
  /// lancement, etc.).
  final Future<void> Function(UserSession session)? onSessionStarted;

  @override
  State<SmartPetApp> createState() => _SmartPetAppState();
}

class _SmartPetAppState extends State<SmartPetApp> {
  late final AuthModel _auth;
  UserSession? _session;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthModel>()..addListener(_sync);
    _sync(rebuild: false);
  }

  @override
  void dispose() {
    _auth.removeListener(_sync);
    _end();
    super.dispose();
  }

  /// Ouvre ou ferme la session selon le compte connecté.
  void _sync({bool rebuild = true}) {
    final user = _auth.status == AuthStatus.signedIn ? _auth.user : null;
    final current = _session;
    // Même compte (ex. nom modifié) : la session continue.
    if (current?.user.id == user?.id && current?.user.role == user?.role) return;
    _end();
    if (user != null) {
      final session = widget.sessionFactory(user);
      _session = session;
      session.load().then((_) => widget.onSessionStarted?.call(session));
    }
    if (rebuild && mounted) setState(() {});
  }

  void _end() {
    final old = _session;
    if (old == null) return;
    _session = null;
    old.close();
    // Les Models sont libérés une fois les écrans du compte retirés.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthModel>().status;
    final session = _session;
    if (session == null) {
      return _app(
        key: const ValueKey('signed-out'),
        home: status == AuthStatus.unknown
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : const SignInScreen(),
      );
    }
    return MultiProvider(
      key: ValueKey('user-${session.user.id}'),
      providers: session.providers,
      child: _app(home: const HomeShell()),
    );
  }

  Widget _app({Key? key, required Widget home}) => MaterialApp(
        key: key,
        title: 'Smart Pet Manager',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      );
}
