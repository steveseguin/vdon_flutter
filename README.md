# VDO.Ninja's Flutter app.

## Features

- supports camera and mic sharing to VDO.Ninja on Android and iOS.
- supports screen-sharing on Android, with mic support available
- can work when in the background, at least until battery-saving mode of some phones kick in
- can work with custom domains, other than vdo.ninja; just replace vdo.ninja with your own domain

![IMG_2049](https://user-images.githubusercontent.com/2575698/151709718-66d589ee-5ed3-4249-8646-f16491ca2a82.jpg) ![IMG_2050](https://user-images.githubusercontent.com/2575698/151709736-b0ca7d6a-484f-4bb5-8669-ce9a06002991.jpg) ![IMG_2051](https://user-images.githubusercontent.com/2575698/151709732-d9729049-b7d3-4c90-8e2e-b0bc1a1b094f.jpg) ![IMG_2053](https://user-images.githubusercontent.com/2575698/151709726-af6303bb-3a91-4d09-b4db-ac3af0e1583e.jpg)


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
