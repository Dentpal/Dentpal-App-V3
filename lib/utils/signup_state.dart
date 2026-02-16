/// Tracks whether the user is currently in the signup flow
/// Used to prevent auth state changes from triggering navigation during signup
class SignupState {
  static bool isInSignupFlow = false;
}
