/// Configuration API, modifiable sans toucher au code :
/// flutter run --dart-define=API_BASE_URL=https://mon-serveur/api/v1/
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://educadim.onrender.com/api/v1/',
  );
  static const String siteUrl = 'https://educadim.onrender.com';
  static const String signupWebUrl =
      'https://educadim.onrender.com/fr/accounts/inscription/';
  static const Duration connectTimeout = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 60);
}

/// Contrat API confirmé d'après mobile_api/ du dépôt Django (urls, views,
/// serializers, README).
class ApiContract {
  static const String loginPath = 'auth/login/'; // confirmé (POST)
  static const String loginIdentifierField = 'username'; // confirmé : e-mail OU user_id
  static const String loginPasswordField = 'password'; // confirmé
  static const String accessTokenKey = 'access'; // confirmé
  static const String refreshTokenKey = 'refresh'; // confirmé (rotation activée)
  static const String refreshPath = 'auth/token/refresh/'; // confirmé
}
