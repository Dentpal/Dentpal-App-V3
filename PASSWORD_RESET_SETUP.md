# Password Reset Setup - DentPal

## ✅ What's Been Implemented

### Mobile App (In-App Reset)

- ✅ Created `reset_password_page.dart` - Beautiful in-app password reset screen
- ✅ Updated `deep_link_service.dart` - Handles password reset deep links
- ✅ Updated `forgot_password.dart` - Configured for mobile deep linking
- ✅ Package names configured: `com.rrnewtech.dentpal`

### Web (Custom Page)

- ✅ Created `web/reset-password.html` - Custom branded password reset page
- ✅ Firebase configuration added
- ✅ Fully functional password reset form

## 🎯 How It Works

### Mobile Users:

1. User requests password reset in the mobile app
2. Receives email with reset link
3. Clicks link → **Opens directly in the app** (no browser!)
4. Resets password in a beautiful in-app screen
5. Redirected to login automatically

### Web Users:

1. User requests password reset on the website
2. Receives email with reset link
3. Clicks link → Opens at `https://dentpal.shop/reset-password`
4. Resets password on the custom branded page
5. Redirected back to website

## 📋 Deployment Steps

### Step 1: Upload the Custom Web Page

Upload the file `/web/reset-password.html` to your `dentpal.shop` server so it's accessible at:

```
https://dentpal.shop/reset-password
```

**How to deploy:**

- If using Firebase Hosting for dentpal.shop, add the file to your `public` folder
- If using a different host, upload via FTP/SSH to your web server
- Make sure the URL exactly matches: `https://dentpal.shop/reset-password`

### Step 2: Configure Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **dentpal-161e5**
3. Navigate to **Authentication → Settings → Authorized domains**
4. Add `dentpal.shop` to the list (if not already there)
5. Click **Save**

### Step 3: Configure iOS (if needed)

Add URL scheme to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>com.rrnewtech.dentpal</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>dentpal</string>
    </array>
  </dict>
</array>
```

Also add to the same file (for Universal Links):

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:dentpal.shop</string>
</array>
```

### Step 4: Configure Android (if needed)

The deep link is already configured in your `android/app/build.gradle.kts` with:

```
namespace = "com.rrnewtech.dentpal"
```

Add intent filter to `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="dentpal.shop" />
</intent-filter>
```

### Step 5: Test the Flow

#### Test Mobile:

1. Open the app on a real device
2. Go to Forgot Password
3. Enter your email
4. Check email on the **same device**
5. Tap the reset link
6. Should open in-app password reset screen

#### Test Web:

1. Go to dentpal.shop on a browser
2. Navigate to Forgot Password
3. Enter your email
4. Check email
5. Click the reset link
6. Should open at dentpal.shop/reset-password

## 🔧 Troubleshooting

### Mobile link opens in browser instead of app:

- Make sure the app is installed on the device
- Verify iOS Universal Links and Android App Links are configured
- Check that `handleCodeInApp: true` in `forgot_password.dart`

### Web page shows 404:

- Verify `reset-password.html` is uploaded to the correct location
- Check that it's accessible at exactly `https://dentpal.shop/reset-password`
- Ensure Firebase authorized domains includes `dentpal.shop`

### Password reset fails:

- Check Firebase Console → Authentication → Settings
- Verify email templates are enabled
- Ensure `dentpal.shop` is in authorized domains

## 📱 Files Modified

1. **`lib/reset_password_page.dart`** (NEW) - In-app password reset screen
2. **`lib/services/deep_link_service.dart`** (UPDATED) - Handles reset deep links
3. **`lib/forgot_password.dart`** (UPDATED) - Configured ActionCodeSettings
4. **`web/reset-password.html`** (NEW) - Custom web reset page

## 🎨 Customization

### Change Web Page Styling:

Edit `web/reset-password.html` - all styles are in the `<style>` tag

### Change Mobile App Styling:

Edit `lib/reset_password_page.dart` - uses your existing `AppColors` and `AppTextStyles`

### Change Redirect URLs:

- Mobile: Edit success dialog in `reset_password_page.dart`
- Web: Edit `window.location.href` in `reset-password.html`

## ✨ Benefits

- **Seamless mobile experience** - No browser context switching
- **Branded web experience** - Custom page matches your website
- **Consistent UX** - Both platforms have beautiful, user-friendly flows
- **Secure** - Uses Firebase's secure password reset codes
- **Professional** - Matches modern app standards

---

**Ready to deploy!** 🚀
