/// App Configuration
/// Centralized configuration for app-wide constants
class AppConfig {
  /// Private constructor to prevent instantiation
  AppConfig._();

  /// App Information
  static const String appName = 'Dentpal';
  static const String appDescription = 
      'The first dental e-commerce store for dental professionals and practitioners.';
  
  /// The one inbox that receives mail, and the only address the app prints.
  ///
  /// There used to be three — support@, privacy@ and business@ on dentpal.com,
  /// plus dev@ and admin@dental.shop written into two screens by hand. None of
  /// the dentpal.com ones resolve, so every surface that asks someone to write
  /// to us points here. Split them again only when there is a second mailbox
  /// actually being read.
  static const String contactEmail = 'admin@dentpal.shop';
  
  /// Legal URLs (for Google Play Console and external links)
  static const String privacyPolicyUrl = 'https://dentpal.shop/privacy-policy';
  static const String termsOfServiceUrl = 'https://dentpal.shop/terms-of-service';
  static const String websiteUrl = 'https://dentpal.shop';

  /// Company Information
  static const String companyName = 'R&R Newtech Dental Corporation';
  static const String companyAddress = 'Unit 1207 Cityland Herrera Tower, Rufino St., cor. Valero St., Salcedo Village, Makati, Philippines, 1227'; // TODO: Update
  
  /// Social Media (if applicable)
  static const String facebookUrl = 'https://www.facebook.com/rnrnewtechdentalcorp/';
  static const String instagramUrl = 'https://www.instagram.com/rrnewtechdentalcorp/';
  
  /// Firebase Deep Links
  static const String productionDomain = 'dentpal-store.web.app';
  static const String sandboxDomain = 'dentpal-store-sandbox-testing.web.app';
  
  /// Feature flags
  ///
  /// Reward points are still earned on every completed order — the trigger in
  /// Cloud Functions credits them regardless — but the page that explains the
  /// tiers and what they unlock is held back until the perks behind them are
  /// real. Flip this to true to bring the page and its Profile row back.
  static const bool rewardPointsPageEnabled = false;

  /// API Keys (Note: Consider using environment variables for sensitive data)
  /// Google Maps API Key is in AndroidManifest.xml
  static const String googleMapsApiKey = 'AIzaSyBncNj8YjWmg-3XkSCqKIujzXihb6e8ZzI';
}
