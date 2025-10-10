// Web implementation using dart:html
import 'dart:html' as html;

String getCurrentPathImpl() {
  // First check the hash for client-side routing
  final hash = html.window.location.hash;
  if (hash.isNotEmpty && hash.startsWith('#/')) {
    return hash.substring(1); // Remove the # to get the path
  }
  // Fallback to pathname for traditional routing
  return html.window.location.pathname ?? '/';
}

// Update the URL without reloading the page (for web deep linking)
void updateUrlImpl(String path) {
  if (path.startsWith('/')) {
    // Use hash-based routing for client-side navigation
    html.window.history.replaceState(null, '', '#$path');
  }
}