// Mobile implementation (no-op for most web utilities)

String getCurrentPathImpl() => '/';

Map<String, String> getQueryParameters() => {};

// No-op for mobile platforms
void updateUrlImpl(String path) {
  // Mobile doesn't need URL updates
}