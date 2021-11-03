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
```
git clone https://github.com/steveseguin/vdon_flutter
cd vdon_flutter
flutter packages get
flutter run
```

### How to build for Android
```
flutter build apk
```

## Supported viewer-side flags

- &codec
- &bitrate
- &audiobitrate
- &scale

The viewer requires &password=false to be used.

## Contributions welcomed

- UVC / USB camera and microphone support is very much welcomed
- Screen share support added to iOS is very much welcomed
