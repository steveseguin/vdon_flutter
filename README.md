# VDO.Ninja's Flutter app.

## Features

- supports camera and mic sharing to VDO.Ninja on Android and iOS.
- supports screen-sharing on Android, with mic support available
- can work when in the background, at least until battery-saving mode of some phones kick in
- can work with custom domains, other than vdo.ninja; just replace vdo.ninja with your own domain

![image](https://user-images.githubusercontent.com/2575698/140071038-4ec561f5-93a1-4171-aafa-e51563ed38af.png)


## Limitations

- does not support group rooms yet
- does not support encrypted handshakes yet (passwords must be set false)
- screen-share does not yet work on iOS
- no UVC / external camera support
- *some* cameras won't be supported
- not at feature partity with web-app version of VDO.Ninja

## Compiled Android APK:

https://drive.google.com/file/d/1M0kv5nWLtcfl2JOnsAGiG1zUmkeIVLyZ/view?usp=sharing


## How to deploy and run app

You'll need flutter installed and added to your PATH first:
https://docs.flutter.dev/get-started/install

You'll also need Android Studio I suppose installed and setup,

But then,to run,
```
git clone https://github.com/steveseguin/vdon_flutter
cd vdon_flutter
flutter packages get
flutter run
```
This works okay for Android; macOS users might want to use Xcode directly instead.  

Mac users building with xcode may also want to have a real iOS device attached for this to work.

### How to build for Android
```
flutter build apk
```

### How to build for iOS

You'll need to install Flutter and add it to your PATH. You'll also need Xcode installed:
https://docs.flutter.dev/get-started/install/macos

You may need to install cocoapods, etc. `sudo gem install cocoapods` for example.

From the `ios` folder, you may want to try installing the gems there or whatever is needed.

Once Flutter is installed, Just open the project with XCode, connect a real iOS device to the system, and build the app. The project should be in the ios folder of the repo.

You may need a developer certificate from Apple to build iOS; Apple might have free ones available for testing only, but otherwise, ~ $100 USD.

## Supported viewer-side flags

- &codec
- &bitrate
- &audiobitrate
- &scale

The viewer requires &password=false to be used.

## Contributions welcomed

- UVC / USB camera and microphone support is very much welcomed
- Screen share support added to iOS is very much welcomed
