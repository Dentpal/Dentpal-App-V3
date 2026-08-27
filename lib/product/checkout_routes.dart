/// The browser paths the checkout flow answers to.
///
/// Checkout is a branch of the Cart destination, not a sibling of it, and the
/// URLs now say so: everything a buyer does between "Proceed to checkout" and
/// the receipt lives under `/cart/checkout`. Kept in one file — rather than as
/// string literals at each `Navigator.push` — because four separate places
/// need to agree on them: the cart that pushes checkout, `main.dart` which has
/// to decide what a cold load of each one means, `AppShell` which lands the
/// payment redirect, and the pages themselves.
library;

/// The checkout form itself.
const String kCheckoutPath = '/cart/checkout';

/// Where a completed payment lands, and where a cancelled or failed one does.
///
/// These two are the only paths in the flow that survive a cold load: the
/// payment provider redirects a *browser* here, so they have to stand up with
/// no route stack underneath them.
const String kCheckoutSuccessPath = '$kCheckoutPath/success';
const String kCheckoutFailedPath = '$kCheckoutPath/fail';

/// The hosted payment page for one PayMongo checkout session.
///
/// The session id is the whole identity of the page — it is what the provider
/// keys the payment to — so it is the last segment rather than a query
/// parameter.
String checkoutSessionPath(String sessionId) => '$kCheckoutPath/$sessionId';

/// Whether [path] belongs to the checkout flow at all.
bool isCheckoutPath(String path) {
  final normalised = path.split('?').first.split('#').first;
  return normalised == kCheckoutPath || normalised.startsWith('$kCheckoutPath/');
}

/// Whether [path] is one of the two endings, which a cold load can serve.
///
/// Every other checkout path needs state that only the previous screen has —
/// a cart of selected items, a live payment session — so a cold load of one
/// has nothing to render and belongs back at the cart.
bool isCheckoutOutcomePath(String path) {
  final normalised = path.split('?').first.split('#').first;
  return normalised == kCheckoutSuccessPath ||
      normalised == kCheckoutFailedPath;
}
