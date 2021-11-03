# VDO.Ninja's Flutter app.

## Features

- supports camera and mic sharing to VDO.Ninja on Android and iOS.
- supports screen-sharing on Android, with mic support available
- can work when in the background, at least until battery-saving mode of some phones kick in

![image](https://user-images.githubusercontent.com/2575698/140070590-48cc21d6-ec7d-47de-9cf3-dee525474579.png)

## Limitations

- does not support group rooms yet
- does not support encrypted handshakes yet (passwords must be set false)
- screen-share does not yet work on iOS
- no UVC / external camera support
- *some* cameras won't be supported

## Compiled Android APK:

https://drive.google.com/file/d/1M0kv5nWLtcfl2JOnsAGiG1zUmkeIVLyZ/view?usp=sharing


## Usage
```
git clone https://github.com/steveseguin/vdon_flutter
cd vdon_flutter
flutter packages get
flutter run
```

## Supported viewer flags

- &codec
- &bitrate
- &audiobitrate
- &scale

The viewer requires &password=false to be used.
