/// Configuration API, modifiable sans toucher au code :
/// flutter run --dart-define=API_BASE_URL=https://mon-serveur/api/v1/
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://educadim.onrender.com/api/v1/',
  );
  static const String signupWebUrl =
      'https://educadim.onrender.com/fr/accounts/inscription/';
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// Contrat API. Seul `loginPath` est confirmé par le cahier des charges.
/// Chaque valeur marquée "À VÉRIFIER" n'a PAS pu être confrontée au backend
/// et doit être validée avec le dépôt Django (voir docs/API_CONTRACT.md).
class ApiContract {
  static const String loginPath = 'auth/login/'; // confirmé (POST)
  static const String loginIdentifierField = 'email'; // À VÉRIFIER (email|username)
  static const String loginPasswordField = 'password'; // À VÉRIFIER
  static const String accessTokenKey = 'access'; // À VÉRIFIER (SimpleJWT usuel)
  static const String refreshTokenKey = 'refresh'; // À VÉRIFIER
  static const String refreshPath = 'auth/refresh/'; // À VÉRIFIER
}
