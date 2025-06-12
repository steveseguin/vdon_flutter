# Deploy to iPhone - Instructions

The pod install has completed successfully! Now follow these steps to deploy to your iPhone:

## 1. Open Xcode
Double-click on `/Users/steveseguin/Code/vdon_flutter/ios/Runner.xcworkspace`
(Important: Open the .xcworkspace file, NOT the .xcodeproj file)

## 2. Configure Signing
1. Select the "Runner" project in the navigator
2. Select the "Runner" target
3. Go to the "Signing & Capabilities" tab
4. Check "Automatically manage signing"
5. Select your Team: H3CKR5XB3J
6. Repeat for the "VDOBroadcastExtension" and "broadcast-ui" targets

## 3. Select Device
1. In the toolbar at the top, click on the device selector
2. Choose "Steves iPhone" from the list

## 4. Build and Run
1. Click the Play button (▶️) or press Cmd+R
2. If prompted, enter your Mac password to allow code signing
3. The app will build and deploy to your iPhone

## 5. First Time on Device
If you see "Untrusted Developer" on your iPhone:
1. Go to Settings → General → VPN & Device Management
2. Find your developer profile and tap it
3. Tap "Trust [Your Developer Name]"
4. Tap "Trust" again in the popup

## Troubleshooting
- If you get "No account" errors, go to Xcode → Settings → Accounts and add your Apple ID
- If provisioning fails, try unchecking and rechecking "Automatically manage signing"
- Make sure your iPhone is unlocked and connected via USB

The app will then launch on your device with all the Flutter plugins properly integrated!