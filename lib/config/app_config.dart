/// App Configuration
/// Centralized configuration for app-wide constants
class AppConfig {
  /// Private constructor to prevent instantiation
  AppConfig._();

  /// App Information
  static const String appName = 'Dentpal';
  static const String appDescription = 
      'The first dental e-commerce store for dental professionals and practitioners.';
  
  /// Contact Information
  static const String supportEmail = 'support@dentpal.com';
  static const String privacyEmail = 'privacy@dentpal.com';
  static const String businessEmail = 'business@dentpal.com';
  
  /// Legal URLs (for Google Play Console and external links)
  static const String privacyPolicyUrl = 'https://dentpal-store.web.app/privacy-policy';
  static const String termsOfServiceUrl = 'https://dentpal-store.web.app/terms-of-service';
  static const String websiteUrl = 'https://dentpal-store.web.app';
  
  /// Company Information
  static const String companyName = 'R&R Newtech Dental Corporation';
  static const String companyAddress = 'Your Business Address'; // TODO: Update
  
  /// Social Media (if applicable)
  static const String facebookUrl = ''; // TODO: Add if available
  static const String instagramUrl = ''; // TODO: Add if available
  
  /// Firebase Deep Links
  static const String productionDomain = 'dentpal-store.web.app';
  static const String sandboxDomain = 'dentpal-store-sandbox-testing.web.app';
  
  /// API Keys (Note: Consider using environment variables for sensitive data)
  /// Google Maps API Key is in AndroidManifest.xml
  static const String googleMapsApiKey = 'AIzaSyBncNj8YjWmg-3XkSCqKIujzXihb6e8ZzI';
}
