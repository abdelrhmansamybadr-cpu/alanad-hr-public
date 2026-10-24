/// App-wide constants.
class AppConfig {
  /// Base URL of the API server (https; SSL is on for the host).
  static const String baseUrl = String.fromEnvironment('API_BASE', defaultValue: 'https://alanadhr.quadrocloud.net');

  /// Tells the server which edition is calling, so it only accepts Al Anad's people (see php-backend/helpers/app_lock.php).
  static const String appId = 'alanad';

  /// Product name shown before a company's own branding is loaded.
  static const String productName = 'Al Anad HR';

  /// Default brand colours (used on the sign-in screens and until a company sets its own).
  static const int defaultPrimary = 0xFF00617A;
  /// Al Anad edition: ignore the company's own colours and always show the Al Anad brand.
  static const bool lockBrand = true;
  static const int defaultAccent = 0xFFC88453;
}
