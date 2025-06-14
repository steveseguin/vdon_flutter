// main.dart
import 'dart:core';
import 'package:flutter/foundation.dart'
show debugDefaultTargetPlatformOverride;
import 'package:vdo_ninja/theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:convert';
import 'src/call_sample/call_sample.dart';
import 'src/route_item.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'dart:async'; 
import 'dart:ui' as ui;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'src/models/social_stream_config.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =  FlutterLocalNotificationsPlugin();
	
Future<bool> isIosVersionSupported() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
  String systemVersion = iosInfo.systemVersion ?? '0';

  // Compare the current iOS version with the minimum required version (16.4)
  if (double.tryParse(systemVersion) != null && double.parse(systemVersion) < 16.4) {
    return false;
  }

  return true;
}

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );
}

Future<void> requestBatteryOptimizationExemption() async {
  if (Platform.isAndroid) {
    final status = await Permission.ignoreBatteryOptimizations.status;
    
    if (!status.isGranted) {
      try {
        await Permission.ignoreBatteryOptimizations.request();
      } catch (e) {
        print("Error requesting battery optimization exemption: $e");
      }
    }
  }
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize notifications first
    await initializeNotifications();
    
    // Temporarily disabled - TODO: Fix foreground service
    /*
    if (Platform.isAndroid) {
      await configureBackgroundService();
    }
    */

    if (WebRTC.platformIsDesktop) {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    } 
    
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    runApp(MyApp());
  }, (error, stackTrace) {
    print('Caught error: $error');
    print(stackTrace);
  });
}

const notificationChannelId = 'vdo_ninja_foreground';
const notificationId = 888;

Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();
  
  if (Platform.isAndroid) {
    // Create the Android notification channel with lower importance
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId, // id
      'VDO.Ninja Service', // name
      description: 'Enables background audio/video streaming', // description
      importance: Importance.low, // Lower importance to be less intrusive
      enableVibration: false, // Disable vibration
      showBadge: false, // Don't show badge on app icon
    );

    // Create the notification channel
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  
  // Configure the service only once at startup
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackground,
      autoStart: false,  // Don't auto-start
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'VDO.Ninja running in background',
      initialNotificationContent: 'Tap to return to app',
      foregroundServiceNotificationId: notificationId,
      foregroundServiceTypes: [
        AndroidForegroundType.camera,
        AndroidForegroundType.microphone,
        AndroidForegroundType.mediaProjection,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStartBackground,
      onBackground: onIosBackground,
    ),
  );
}

Future<bool> startForegroundService() async {
  final service = FlutterBackgroundService();
  // Just start the already configured service
  return await service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
Future<void> onStartBackground(ServiceInstance service) async {
  // Initialize Flutter widgets binding for isolate
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications in the isolate
  await initializeNotifications();
  
  // For Android 12+ we need to immediately show a notification
  if (service is AndroidServiceInstance) {
    // Set as foreground service first
    service.setAsForegroundService();
    
    // Show notification immediately  
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      notificationChannelId,
      'VDO.Ninja Service',
      channelDescription: 'Enables background audio/video streaming',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showWhen: false,
      enableVibration: false,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );
    
    // Show notification directly through flutter_local_notifications
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      'VDO.Ninja is running in background',
      'Tap to return to the app',
      notificationDetails,
    );
    
    // Also set through the service
    service.setForegroundNotificationInfo(
      title: 'VDO.Ninja is running in background',
      content: 'Tap to return to the app',
    );
    
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  // Reduce update frequency to save battery
  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      try {
        await service.setForegroundNotificationInfo(
          title: 'VDO.Ninja is active',
          content: 'Tap to return to the app',
        );
      } catch (e) {
        print('Error updating notification: $e');
      }
    }
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

String streamID = "";
String roomID = "";
String password = "";
bool quality = false;
bool advanced = false;
bool landscape = false;
bool useCustomBitrate = false;
int customBitrate = 0;
bool enableSystemAudio = false; // System audio capture for screen sharing
String WSSADDRESS = 'wss://wss.vdo.ninja:443';
String TURNSERVER = 'un;pw;turn:turn.x.co:3478';
String customSalt = 'vdo.ninja';

// Social Stream configuration
SocialStreamConfig socialStreamConfig = SocialStreamConfig(
  sessionId: '',
  mode: ConnectionMode.websocket, // Default to websocket since WebRTC not implemented
  password: 'false',
  enabled: false,
);


String _selectedMicrophoneId = 'default';
List<MediaDeviceInfo> _microphones = [];

enum DialogDemoAction {
  cancel,
  connect,
}

class _MyAppState extends State<MyApp> {
  List<RouteItem> items = [];
  late SharedPreferences _prefs;
  var _deviceID = "screen";
  List<Color> colors = const [
    Color(0xFFA53E97),
    Color(0xFF645098),
    Color(0xFF33517E),
    Colors.amber,
    Colors.red,
    Color(0xFF133511),  // Fixed the format of these colors
    Color(0xFF233512),
    Color(0xFF333513),
    Color(0xFF433514),
    Color(0xFF533515),
    Color(0xFF633516),
    Color(0xFF733517),
    Color(0xFF833518),
    Color(0xFF933519),
    Color(0xFF335110),
    Color(0xFF335171),
    Color(0xFF335172),
    Color(0xFF335173),
    Color(0xFF335174),
    Color(0xFF335175)
  ];
  
  @override
  initState() {
    super.initState();
    _initData();
    _initItems();
  }
  
  _buildRow(context, item, index) {
    return Card(
      margin: EdgeInsets.only(top: 20, left: 20, right: 20),
      color: colors[index],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
          child: ListTile(
            title: Text(
              item.title,
              style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
            onTap: () => item.push(context),
            trailing: Icon(Icons.arrow_right),
            leading: Icon(
              item.icon,
              size: 30,
              color: Colors.white,
            ),
          ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text('VDO.Ninja'),
          backgroundColor: Colors.blue,
        ),
        body: Container(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 25, 0, 0),
                        child: Container(
                          width: double.infinity,
                          child: Text(
                            "Share",
                            textAlign: TextAlign.left,
                            style: theme.textTheme.displayLarge!.apply(
                              color: Colors.white,
                              fontWeightDelta: 10,
                              fontSizeFactor: 1.5),
                          ),
                        ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8.0),
                        physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            return _buildRow(context, items[i], i);
                          }),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1)
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Need help or have questions?",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Join our friendly community on Discord for support and tips.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: 12),
                          TextButton.icon(
                            icon: Icon(Icons.discord, color: Colors.white),
                            style: TextButton.styleFrom(
                              backgroundColor: Color(0xFF5865F2),
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => {
                              _openDiscord()
                            },
                            label: Text(
                              "Join Discord Community",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
            ],
          )),
      ),
    );
  }
  
  String _normalizeWSSAddress(String address) {
    // Trim whitespace
    address = address.trim();
    
    // If address is empty, return it as-is (don't add wss://)
    if (address.isEmpty) {
      return address;
    }
    
    // If no protocol is specified, assume wss://
    if (!address.startsWith('ws://') && !address.startsWith('wss://') && 
        !address.startsWith('http://') && !address.startsWith('https://')) {
      address = 'wss://' + address;
    }
    
    // Convert http:// to ws:// and https:// to wss://
    if (address.startsWith('http://')) {
      address = address.replaceFirst('http://', 'ws://');
    } else if (address.startsWith('https://')) {
      address = address.replaceFirst('https://', 'wss://');
    }
    
    return address;
  }

  String _getDefaultSaltFromWSSAddress(String wssAddress) {
    try {
      // If address is empty, return default salt
      if (wssAddress.trim().isEmpty) {
        return 'vdo.ninja';
      }
      
      // Normalize the address first
      wssAddress = _normalizeWSSAddress(wssAddress);
      
      // Parse the URL
      Uri uri = Uri.parse(wssAddress);
      String host = uri.host;
      
      // If host is empty, try to extract from the address directly
      if (host.isEmpty && wssAddress.contains('://')) {
        // Extract the part after :// and before the next / or :
        String afterProtocol = wssAddress.split('://')[1];
        host = afterProtocol.split(RegExp(r'[:/]'))[0];
      }
      
      // Extract the top-level domain (last two parts)
      List<String> parts = host.split('.');
      if (parts.length >= 2) {
        // Handle cases like .co.uk, .com.au etc
        String lastPart = parts[parts.length - 1];
        String secondLastPart = parts[parts.length - 2];
        
        // Check for common two-part TLDs
        if ((lastPart.length == 2 && secondLastPart.length <= 3) || 
            ['com', 'net', 'org', 'edu', 'gov', 'mil', 'co'].contains(secondLastPart)) {
          if (parts.length >= 3) {
            return '${parts[parts.length - 3]}.${secondLastPart}.${lastPart}';
          }
        }
        
        return '${secondLastPart}.${lastPart}';
      }
      return host.isNotEmpty ? host : 'vdo.ninja';
    } catch (e) {
      return 'vdo.ninja';
    }
  }

  void _initData() async {
    if (WebRTC.platformIsAndroid) {
      // Request battery optimization exemption for better performance
      await requestBatteryOptimizationExemption();
      
      // Don't start the foreground service automatically
      // Only start it when the user starts streaming
      // This avoids the ForegroundServiceDidNotStartInTimeException
    }
    
    _prefs = await SharedPreferences.getInstance();
    //await _prefs.clear();
    
    streamID = _prefs.getString('streamID') ?? "";
    roomID = _prefs.getString('roomID') ?? "";
    password = _prefs.getString('password') ?? "";
    
    WSSADDRESS = _normalizeWSSAddress(_prefs.getString('WSSADDRESS') ?? WSSADDRESS);
    TURNSERVER = _prefs.getString('TURNSERVER') ?? TURNSERVER;
    customSalt = _prefs.getString('customSalt') ?? _getDefaultSaltFromWSSAddress(WSSADDRESS);
    // _selectedMicrophoneId = _prefs.getString('audioDeviceId') ?? _selectedMicrophoneId;
    
    // Load Social Stream configuration
    final socialStreamData = _prefs.getString('socialStreamConfig');
    if (socialStreamData != null) {
      try {
        socialStreamConfig = SocialStreamConfig.fromMap(jsonDecode(socialStreamData));
      } catch (e) {
        print('Error loading Social Stream config: $e');
      }
    }
    
    try {
      quality = _prefs.getBool('resolution') ?? false;
    } catch (e) {}
    
    try {
      landscape = _prefs.getBool('landscape') ?? false;
    } catch (e) {}
    
    try {
      advanced = _prefs.getBool('advanced') ?? false;
    } catch (e) {}
    
    try {
      // Only load custom bitrate settings on Android
      if (Platform.isAndroid) {
        useCustomBitrate = _prefs.getBool('useCustomBitrate') ?? false;
        customBitrate = _prefs.getInt('customBitrate') ?? 0;
      } else {
        // Force disable custom bitrate on iOS
        useCustomBitrate = false;
        customBitrate = 0;
      }
      enableSystemAudio = _prefs.getBool('enableSystemAudio') ?? false;
    } catch (e) {}
    
    
    if (streamID == "") {
      var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
      Random _rnd = Random();
      String getRandomString(int length) =>
      String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
      streamID = getRandomString(8);
      _prefs.setString('streamID', streamID);

      if (_prefs.getString('password') == null) {
        _prefs.setString('password', password);
      }
    } else if (_prefs.getString('password') == null) {
      password = "0";
      _prefs.setString('password', password);
    }
    
    streamID = streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    roomID = roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    
    setState(() {
      WakelockPlus.enable();
    });
  }

  
  _showAddressDialog(context) {
    showDialog<DialogDemoAction>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (BuildContext context) {
        return PublishingSettingsDialog(
          initialStreamID: streamID,
          initialRoomID: roomID,
          initialPassword: password,
          initialQuality: quality,
          initialLandscape: landscape,
          initialAdvanced: advanced,
          initialWSSAddress: WSSADDRESS,
          initialTurnServer: TURNSERVER,
          initialCustomSalt: customSalt,
          initialUseCustomBitrate: useCustomBitrate,
          initialCustomBitrate: customBitrate,
          initialEnableSystemAudio: enableSystemAudio,
          initialSocialStreamConfig: socialStreamConfig,
          microphones: _microphones,
          selectedMicrophoneId: _selectedMicrophoneId,
          currentDeviceID: _deviceID,
          onSettingsChanged: (settings) {
            setState(() {
              streamID = settings['streamID'];
              roomID = settings['roomID'];
              password = settings['password'];
              quality = settings['quality'];
              landscape = settings['landscape'];
              advanced = settings['advanced'];
              WSSADDRESS = settings['WSSADDRESS'];
              TURNSERVER = settings['TURNSERVER'];
              customSalt = settings['customSalt'];
              useCustomBitrate = settings['useCustomBitrate'];
              customBitrate = settings['customBitrate'];
              enableSystemAudio = settings['enableSystemAudio'];
              _selectedMicrophoneId = settings['selectedMicrophoneId'];
              socialStreamConfig = settings['socialStreamConfig'] ?? socialStreamConfig;
              
              // Save to preferences
              _prefs.setString('streamID', streamID);
              _prefs.setString('roomID', roomID);
              _prefs.setString('password', password);
              _prefs.setBool('resolution', quality);
              _prefs.setBool('landscape', landscape);
              _prefs.setBool('advanced', advanced);
              
              // Handle empty WSS address - store default instead of empty string
              String wssToStore = WSSADDRESS.trim().isEmpty ? 'wss://wss.vdo.ninja:443' : WSSADDRESS;
              _prefs.setString('WSSADDRESS', wssToStore);
              
              _prefs.setString('TURNSERVER', TURNSERVER);
              _prefs.setString('customSalt', customSalt);
              _prefs.setBool('useCustomBitrate', useCustomBitrate);
              _prefs.setInt('customBitrate', customBitrate);
              _prefs.setBool('enableSystemAudio', enableSystemAudio);
              _prefs.setString('audioDeviceId', _selectedMicrophoneId);
              
              // Save Social Stream configuration
              _prefs.setString('socialStreamConfig', jsonEncode(socialStreamConfig.toMap()));
            });
          },
        );
      },
    ).then<void>((DialogDemoAction? value) {
      if (value == DialogDemoAction.connect) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallSample(
              key: new GlobalKey<ScaffoldState>(),
              streamID: streamID,
              deviceID: _deviceID,
              audioDeviceId: _selectedMicrophoneId,
              roomID: roomID,
              quality: quality,
              landscape: landscape,
              WSSADDRESS: WSSADDRESS,
              TURNSERVER: TURNSERVER,
              password: (password=="") ? "someEncryptionKey123" : password,
              muted: false,
              preview: true,
              mirrored: true,
              customBitrate: useCustomBitrate ? customBitrate : 0,
              customSalt: customSalt,
              enableSystemAudio: enableSystemAudio,
              socialStreamConfig: socialStreamConfig
            )));
      }
    });
  }
  
  _initItems() async {
    items = <RouteItem>[];
    
    // Existing code for iOS version check...
    if (Platform.isIOS) {
      bool versionSupported = await isIosVersionSupported();
      if (!versionSupported) {
        items.add(RouteItem(
          title: 'Update iOS to Screenshare',
          subtitle: 'Screensharing requires iOS 16.4 or newer',
          icon: Icons.screen_share,
          push: (BuildContext context) {
            _deviceID = "screen";
            _showAddressDialog(context);
          }));
      } else {
        items.add(RouteItem(
          title: 'SCREEN',
          subtitle: 'Share your device\'s screen',
          icon: Icons.screen_share,
          push: (BuildContext context) {
            _deviceID = "screen";
            _showAddressDialog(context);
          }));
      }
    } else {
      items.add(RouteItem(
        title: 'SCREEN',
        subtitle: 'Share your device\'s screen',
        icon: Icons.screen_share,
        push: (BuildContext context) {
          _deviceID = "screen";
          _showAddressDialog(context);
        }));
    }
    
    // Rest of the camera/device detection code...
    var devices = await navigator.mediaDevices.enumerateDevices();
    
    for (var item in devices) {
      if (item.kind == "audioinput"){
        // Check if this might be a USB audio device
        String label = item.label;
        bool isUSBDevice = label.toLowerCase().contains('usb') ||
            label.toLowerCase().contains('audio interface') ||
            label.toLowerCase().contains('scarlett') ||
            label.toLowerCase().contains('focusrite') ||
            label.toLowerCase().contains('zoom') ||
            label.toLowerCase().contains('presonus') ||
            label.toLowerCase().contains('behringer') ||
            label.toLowerCase().contains('motu') ||
            label.toLowerCase().contains('rme') ||
            label.toLowerCase().contains('steinberg');
        
        // Add USB device indicator to label
        if (isUSBDevice) {
          label = "🎤 $label (Professional USB)";
        }
        
        MediaDeviceInfo deviceInfo = MediaDeviceInfo(deviceId: item.deviceId, label: label);
        
        // Insert USB devices at the beginning (after default) for easy access
        if (isUSBDevice) {
          _microphones.insert(1, deviceInfo); // After "Default Microphone"
        } else {
          _microphones.add(deviceInfo);
        }
        continue;        
      } 
      if (item.kind != "videoinput") {
        continue;
      }
      var cameraType = "Camera";
      if (item.label.toLowerCase().contains('back')) {
        cameraType = 'Back Camera';
      } else if (item.label.toLowerCase().contains('rear')) {
        cameraType = 'Back Camera';
      } else if (item.label.toLowerCase().contains('user')) {
        cameraType = 'Front Camera';
      } else if (item.label.toLowerCase().contains('front')) {
        cameraType = 'Front Camera';
      } else if (item.label.toLowerCase().contains('environment')) {
        cameraType = 'Rear Camera';
      } else {
        cameraType = item.label;
      }
      items.add(RouteItem(
        title: cameraType.toUpperCase(),
        subtitle: item.label.toString(),
        icon: item.label.toLowerCase().contains('front') ||
        item.label.toLowerCase().contains('user') ?
        Icons.video_camera_front :
        Icons.video_camera_back,
        push: (BuildContext context) {
          _deviceID = item.deviceId;
          _showAddressDialog(context);
        }));
    }
    
    _microphones.insert(0, MediaDeviceInfo(deviceId: 'default', label: 'Default Microphone'));
    
    items.add(RouteItem(
      title: 'MICROPHONE',
      subtitle: 'Share microphone audio only',
      icon: Icons.mic,
      push: (BuildContext context) {
        _deviceID = "microphone";
        _showAddressDialog(context);
      }));
      
    // Enhanced web version menu item 
    items.add(RouteItem(
      title: 'WEB VERSION ★',
      subtitle: 'Full features and better quality/performance',
      icon: Icons.star,
      push: (BuildContext context) {
        _showWebVersionDialog(context);
      },
    ));
    
    items.add(RouteItem(
      title: 'HOW TO USE',
      subtitle: 'A simple guide on using the VDO.Ninja native app',
      icon: Icons.menu_book,
      push: (BuildContext context) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => WebViewScreen(url: "https://nativehelp.vdo.ninja/?app=1")),
        );
      },
    ));
    setState(() {});
  }
  
  void _showWebVersionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Web Version Benefits'),
          backgroundColor: ninjaDialogColor,
          surfaceTintColor: Colors.transparent,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The web version offers:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
                SizedBox(height: 10),
                _benefitItem('Up to 4K video options'),
                _benefitItem('Two-way chat support'),
                _benefitItem('Advanced customization options'),
                _benefitItem('Often better quality video'),
                _benefitItem('Faster reconnection speeds'),
                SizedBox(height: 10),
                const Text('Try the web version at https://vdo.ninja if you experience issues with the native app.',
                  style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)
                ),
              ],
            )
          ),
          actions: [
            TextButton(
              child: Text('CANCEL', 
                style: TextStyle(
                  color: ninjaAccentColor,
                  fontWeight: FontWeight.bold
                )
              ),
              onPressed: () {
                Navigator.pop(context);
              }
            ),
            TextButton(
              child: Text('OPEN WEB VERSION', 
                style: TextStyle(
                  color: ninjaAccentColor,
                  fontWeight: FontWeight.bold
                )
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => WebViewScreen(url: "https://vdo.ninja/?app=1")),
                );
              }
            ),
          ],
        );
      }
    );
  }
  
  Widget _benefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
  
  _openDiscord() async {
    final Uri url = Uri.parse('https://discord.vdo.ninja/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
      throw Exception('Could not launch $url');
    }
  }
}

// Publishing Settings Dialog with proper state management
class PublishingSettingsDialog extends StatefulWidget {
  final String initialStreamID;
  final String initialRoomID;
  final String initialPassword;
  final bool initialQuality;
  final bool initialLandscape;
  final bool initialAdvanced;
  final String initialWSSAddress;
  final String initialTurnServer;
  final String initialCustomSalt;
  final bool initialUseCustomBitrate;
  final int initialCustomBitrate;
  final bool initialEnableSystemAudio;
  final SocialStreamConfig initialSocialStreamConfig;
  final List<MediaDeviceInfo> microphones;
  final String selectedMicrophoneId;
  final String currentDeviceID;
  final Function(Map<String, dynamic>) onSettingsChanged;

  const PublishingSettingsDialog({
    Key? key,
    required this.initialStreamID,
    required this.initialRoomID,
    required this.initialPassword,
    required this.initialQuality,
    required this.initialLandscape,
    required this.initialAdvanced,
    required this.initialWSSAddress,
    required this.initialTurnServer,
    required this.initialCustomSalt,
    required this.initialUseCustomBitrate,
    required this.initialCustomBitrate,
    required this.initialEnableSystemAudio,
    required this.initialSocialStreamConfig,
    required this.microphones,
    required this.selectedMicrophoneId,
    required this.currentDeviceID,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  _PublishingSettingsDialogState createState() => _PublishingSettingsDialogState();
}

class _PublishingSettingsDialogState extends State<PublishingSettingsDialog> {
  late TextEditingController _streamIDController;
  late TextEditingController _roomIDController;
  late TextEditingController _passwordController;
  late TextEditingController _wssAddressController;
  late TextEditingController _turnServerController;
  late TextEditingController _customSaltController;
  late TextEditingController _customBitrateController;
  late TextEditingController _socialStreamSessionController;
  late TextEditingController _socialStreamPasswordController;
  
  late FocusNode _wssAddressFocusNode;
  
  late String streamID;
  late String roomID;
  late String password;
  late bool quality;
  late bool landscape;
  late bool advanced;
  late String WSSADDRESS;
  late String TURNSERVER;
  late String customSalt;
  late bool useCustomBitrate;
  late int customBitrate;
  late bool enableSystemAudio;
  late String _selectedMicrophoneId;
  late SocialStreamConfig socialStreamConfig;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize controllers
    _streamIDController = TextEditingController(text: widget.initialStreamID);
    _roomIDController = TextEditingController(text: widget.initialRoomID);
    _passwordController = TextEditingController(text: widget.initialPassword);
    _wssAddressController = TextEditingController(text: widget.initialWSSAddress);
    _turnServerController = TextEditingController(text: widget.initialTurnServer);
    _customSaltController = TextEditingController(text: widget.initialCustomSalt);
    _customBitrateController = TextEditingController(text: widget.initialCustomBitrate > 0 ? widget.initialCustomBitrate.toString() : '');
    _socialStreamSessionController = TextEditingController(text: widget.initialSocialStreamConfig.sessionId);
    _socialStreamPasswordController = TextEditingController(text: widget.initialSocialStreamConfig.password ?? 'false');
    
    // Initialize focus node
    _wssAddressFocusNode = FocusNode();
    _wssAddressFocusNode.addListener(() {
      if (!_wssAddressFocusNode.hasFocus) {
        // Normalize when user leaves the field
        setState(() {
          WSSADDRESS = _normalizeWSSAddress(_wssAddressController.text);
          _wssAddressController.text = WSSADDRESS;
          
          // Update custom salt based on normalized WSS address
          customSalt = _getDefaultSaltFromWSSAddress(WSSADDRESS);
          _customSaltController.text = customSalt;
        });
        _updateSettings();
      }
    });
    
    // Initialize state
    streamID = widget.initialStreamID;
    roomID = widget.initialRoomID;
    password = widget.initialPassword;
    quality = widget.initialQuality;
    landscape = widget.initialLandscape;
    advanced = widget.initialAdvanced;
    WSSADDRESS = widget.initialWSSAddress;
    TURNSERVER = widget.initialTurnServer;
    customSalt = widget.initialCustomSalt;
    // Force disable custom bitrate on iOS
    if (Platform.isAndroid) {
      useCustomBitrate = widget.initialUseCustomBitrate;
      customBitrate = widget.initialCustomBitrate;
    } else {
      useCustomBitrate = false;
      customBitrate = 0;
    }
    enableSystemAudio = widget.initialEnableSystemAudio;
    _selectedMicrophoneId = widget.selectedMicrophoneId;
    socialStreamConfig = widget.initialSocialStreamConfig;
  }
  
  @override
  void dispose() {
    _streamIDController.dispose();
    _roomIDController.dispose();
    _passwordController.dispose();
    _wssAddressController.dispose();
    _turnServerController.dispose();
    _customSaltController.dispose();
    _customBitrateController.dispose();
    _socialStreamSessionController.dispose();
    _socialStreamPasswordController.dispose();
    _wssAddressFocusNode.dispose();
    super.dispose();
  }
  
  void _updateSettings() {
    widget.onSettingsChanged({
      'streamID': streamID,
      'roomID': roomID,
      'password': password,
      'quality': quality,
      'landscape': landscape,
      'advanced': advanced,
      'WSSADDRESS': WSSADDRESS,
      'TURNSERVER': TURNSERVER,
      'customSalt': customSalt,
      'useCustomBitrate': useCustomBitrate,
      'customBitrate': customBitrate,
      'enableSystemAudio': enableSystemAudio,
      'selectedMicrophoneId': _selectedMicrophoneId,
      'socialStreamConfig': socialStreamConfig,
    });
  }
  
  String _normalizeWSSAddress(String address) {
    address = address.trim();
    
    // If address is empty, return it as-is (don't add wss://)
    if (address.isEmpty) {
      return address;
    }
    
    if (!address.startsWith('ws://') && !address.startsWith('wss://') && 
        !address.startsWith('http://') && !address.startsWith('https://')) {
      address = 'wss://' + address;
    }
    
    if (address.startsWith('http://')) {
      address = address.replaceFirst('http://', 'ws://');
    } else if (address.startsWith('https://')) {
      address = address.replaceFirst('https://', 'wss://');
    }
    
    return address;
  }

  String _getDefaultSaltFromWSSAddress(String wssAddress) {
    try {
      // If address is empty, return default salt
      if (wssAddress.trim().isEmpty) {
        return 'vdo.ninja';
      }
      
      wssAddress = _normalizeWSSAddress(wssAddress);
      Uri uri = Uri.parse(wssAddress);
      String host = uri.host;
      
      if (host.isEmpty && wssAddress.contains('://')) {
        String afterProtocol = wssAddress.split('://')[1];
        host = afterProtocol.split(RegExp(r'[:/]'))[0];
      }
      
      List<String> parts = host.split('.');
      if (parts.length >= 2) {
        String lastPart = parts[parts.length - 1];
        String secondLastPart = parts[parts.length - 2];
        
        if ((lastPart.length == 2 && secondLastPart.length <= 3) || 
            ['com', 'net', 'org', 'edu', 'gov', 'mil', 'co'].contains(secondLastPart)) {
          if (parts.length >= 3) {
            return '${parts[parts.length - 3]}.${secondLastPart}.${lastPart}';
          }
        }
        
        return '${secondLastPart}.${lastPart}';
      }
      return host.isNotEmpty ? host : 'vdo.ninja';
    } catch (e) {
      return 'vdo.ninja';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: ninjaDialogColor.withValues(alpha: 0.95),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Publishing Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context, DialogDemoAction.cancel),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SizedBox(height: 20),
                        // Stream ID TextField
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 12),
                          child: TextField(
                            style: TextStyle(color: Colors.white),
                            controller: _streamIDController,
                            onChanged: (String text) {
                              setState(() {
                                streamID = text;
                              });
                              _updateSettings();
                            },
                            decoration: InputDecoration(
                              hintText: streamID.isEmpty ? "Auto-generated" : streamID,
                              labelText: 'Stream ID (auto-generated if empty)',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintStyle: TextStyle(color: Colors.white30),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: ninjaAccentColor),
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        // Room ID TextField
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 12),
                          child: TextField(
                            style: TextStyle(color: Colors.white),
                            controller: _roomIDController,
                            onChanged: (String text) {
                              setState(() {
                                roomID = text;
                              });
                              _updateSettings();
                            },
                            decoration: InputDecoration(
                              hintText: "Room name",
                              labelText: 'Room name (optional)',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintStyle: TextStyle(color: Colors.white30),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: ninjaAccentColor),
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        // Password TextField
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 12),
                          child: TextField(
                            style: TextStyle(color: Colors.white),
                            controller: _passwordController,
                            onChanged: (String textpass) {
                              setState(() {
                                password = textpass;
                              });
                              _updateSettings();
                            },
                            decoration: InputDecoration(
                              hintText: "Password",
                              labelText: 'Password (optional)',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintStyle: TextStyle(color: Colors.white30),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: ninjaAccentColor),
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        // Microphone Dropdown
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Microphone',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white30),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<String>(
                                  value: _selectedMicrophoneId,
                                  dropdownColor: ninjaDialogColor,
                                  style: TextStyle(color: Colors.white),
                                  isExpanded: true,
                                  underline: SizedBox(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedMicrophoneId = newValue;
                                      });
                                      _updateSettings();
                                    }
                                  },
                                  items: widget.microphones.map<DropdownMenuItem<String>>((MediaDeviceInfo device) {
                                    return DropdownMenuItem<String>(
                                      value: device.deviceId,
                                      child: Text(device.label, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Divider
                        Divider(color: Colors.white30, height: 32),
                        
                        // Quality Switch
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SwitchListTile(
                            title: const Text('Prefer 1080p', style: TextStyle(color: Colors.white)),
                            subtitle: Text(quality ? '1920x1080 @ 30fps' : '1280x720 @ 30fps', 
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: quality,
                            activeColor: ninjaAccentColor,
                            onChanged: (bool value) {
                              setState(() {
                                quality = value;
                              });
                              _updateSettings();
                            }
                          ),
                        ),
                        
                        // Landscape Switch
                        Container(
                          margin: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SwitchListTile(
                            title: const Text('Force landscape', style: TextStyle(color: Colors.white)),
                            subtitle: Text('Lock orientation to landscape mode', 
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: landscape,
                            activeColor: ninjaAccentColor,
                            onChanged: (bool value) {
                              setState(() {
                                landscape = value;
                              });
                              _updateSettings();
                            }
                          ),
                        ),
                        
                        // Advanced Settings Toggle
                        Container(
                          margin: EdgeInsets.only(top: 16, bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SwitchListTile(
                            title: const Text('Advanced Settings', style: TextStyle(color: Colors.white)),
                            subtitle: Text('Show additional configuration options', 
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: advanced,
                            activeColor: ninjaAccentColor,
                            onChanged: (bool value) {
                              setState(() {
                                advanced = value;
                              });
                              _updateSettings();
                            }
                          ),
                        ),
                        
                        // Advanced Settings Section
                        if (advanced) ...[
                          SizedBox(height: 16),
                          
                          // WSS Address TextField with validation
                          Container(
                            margin: EdgeInsets.symmetric(vertical: 12),
                            child: TextField(
                              style: TextStyle(color: Colors.white),
                              controller: _wssAddressController,
                              focusNode: _wssAddressFocusNode,
                              onChanged: (String text) {
                                // Store raw input without normalization during typing
                                setState(() {
                                  WSSADDRESS = text; // Store raw input
                                });
                                _updateSettings();
                              },
                              decoration: InputDecoration(
                                hintText: WSSADDRESS,
                                labelText: 'Handshake server',
                                helperText: 'Leave empty for default. Auto-formats when you finish typing.',
                                helperStyle: TextStyle(color: Colors.white54),
                                labelStyle: TextStyle(color: Colors.white70),
                                hintStyle: TextStyle(color: Colors.white30),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: ninjaAccentColor),
                                ),
                                errorText: _validateWSSAddress(WSSADDRESS),
                                errorStyle: TextStyle(color: Colors.red),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          
                          // Custom Salt TextField
                          Container(
                            margin: EdgeInsets.symmetric(vertical: 12),
                            child: TextField(
                              style: TextStyle(color: Colors.white),
                              controller: _customSaltController,
                              onChanged: (String text) {
                                setState(() {
                                  customSalt = text;
                                });
                                _updateSettings();
                              },
                              decoration: InputDecoration(
                                hintText: customSalt,
                                labelText: 'Custom Salt',
                                helperText: 'Default: Top domain from handshake server',
                                helperStyle: TextStyle(color: Colors.white54),
                                labelStyle: TextStyle(color: Colors.white70),
                                hintStyle: TextStyle(color: Colors.white30),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: ninjaAccentColor),
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          
                          // TURN Server TextField
                          Container(
                            margin: EdgeInsets.symmetric(vertical: 12),
                            child: TextField(
                              style: TextStyle(color: Colors.white),
                              controller: _turnServerController,
                              onChanged: (String text) {
                                setState(() {
                                  TURNSERVER = text;
                                });
                                _updateSettings();
                              },
                              decoration: InputDecoration(
                                hintText: TURNSERVER,
                                labelText: 'TURN server',
                                labelStyle: TextStyle(color: Colors.white70),
                                hintStyle: TextStyle(color: Colors.white30),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: ninjaAccentColor),
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          
                          // Custom Bitrate Switch (Android only - iOS doesn't support setParameters)
                          if (Platform.isAndroid) ...[
                            Container(
                              margin: EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SwitchListTile(
                                title: const Text('Custom bitrate', style: TextStyle(color: Colors.white)),
                                subtitle: Text('Override default video bitrate', 
                                  style: TextStyle(color: Colors.white54, fontSize: 12)),
                                value: useCustomBitrate,
                                activeColor: ninjaAccentColor,
                                onChanged: (bool value) {
                                  setState(() {
                                    useCustomBitrate = value;
                                  });
                                  _updateSettings();
                                }
                              ),
                            ),
                            
                            // Custom Bitrate Input with validation
                            if (useCustomBitrate)
                              Container(
                                margin: EdgeInsets.symmetric(vertical: 12),
                                child: TextField(
                                  style: TextStyle(color: Colors.white),
                                  controller: _customBitrateController,
                                  keyboardType: TextInputType.number,
                                  onChanged: (String text) {
                                    setState(() {
                                      customBitrate = int.tryParse(text) ?? 0;
                                    });
                                    _updateSettings();
                                  },
                                  decoration: InputDecoration(
                                    hintText: quality ? "10000" : "6000",
                                    labelText: 'Bitrate (kbps)',
                                    helperText: 'Default: ${quality ? "10000" : "6000"} kbps. Range: 100-50000',
                                    helperStyle: TextStyle(color: Colors.white54),
                                    labelStyle: TextStyle(color: Colors.white70),
                                    hintStyle: TextStyle(color: Colors.white30),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white30),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: ninjaAccentColor),
                                    ),
                                    errorText: _validateBitrate(customBitrate),
                                    errorStyle: TextStyle(color: Colors.red),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                          
                          // Social Stream Integration
                          SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.purple.withOpacity(0.5)),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.purple.withOpacity(0.1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.chat_bubble, color: Colors.purple, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Social Stream Ninja Integration',
                                      style: TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                
                                // Enable Social Stream Toggle
                                SwitchListTile(
                                  title: const Text('Enable Social Stream', style: TextStyle(color: Colors.white)),
                                  subtitle: Text('Receive chat messages from Social Stream Ninja', 
                                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  value: socialStreamConfig.enabled,
                                  activeColor: Colors.purple,
                                  onChanged: (bool value) {
                                    setState(() {
                                      socialStreamConfig = SocialStreamConfig(
                                        sessionId: socialStreamConfig.sessionId,
                                        mode: socialStreamConfig.mode,
                                        password: socialStreamConfig.password,
                                        enabled: value,
                                      );
                                    });
                                    _updateSettings();
                                  }
                                ),
                                
                                if (socialStreamConfig.enabled) ...[
                                  SizedBox(height: 12),
                                  
                                  // Session ID Input
                                  TextField(
                                    style: TextStyle(color: Colors.white),
                                    controller: _socialStreamSessionController,
                                    onChanged: (String text) {
                                      setState(() {
                                        socialStreamConfig = SocialStreamConfig(
                                          sessionId: text,
                                          mode: socialStreamConfig.mode,
                                          password: socialStreamConfig.password,
                                          enabled: socialStreamConfig.enabled,
                                        );
                                      });
                                      _updateSettings();
                                    },
                                    decoration: InputDecoration(
                                      hintText: "Enter Social Stream session ID",
                                      labelText: 'Social Stream Session ID',
                                      helperText: 'The session ID from Social Stream Ninja',
                                      helperStyle: TextStyle(color: Colors.white54),
                                      labelStyle: TextStyle(color: Colors.white70),
                                      hintStyle: TextStyle(color: Colors.white30),
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(color: Colors.white30),
                                      ),
                                      focusedBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(color: Colors.purple),
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  SizedBox(height: 12),
                                  
                                  // Connection Mode Selector
                                  Container(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Connection Mode',
                                          style: TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                        SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: RadioListTile<ConnectionMode>(
                                                title: Text('WebRTC', style: TextStyle(color: Colors.white, fontSize: 14)),
                                                subtitle: Text('Lower latency', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                                value: ConnectionMode.webrtc,
                                                groupValue: socialStreamConfig.mode,
                                                activeColor: Colors.purple,
                                                onChanged: (ConnectionMode? value) {
                                                  if (value != null) {
                                                    setState(() {
                                                      socialStreamConfig = SocialStreamConfig(
                                                        sessionId: socialStreamConfig.sessionId,
                                                        mode: value,
                                                        password: value == ConnectionMode.webrtc ? (socialStreamConfig.password ?? 'false') : null,
                                                        enabled: socialStreamConfig.enabled,
                                                      );
                                                    });
                                                    _updateSettings();
                                                  }
                                                },
                                              ),
                                            ),
                                            Expanded(
                                              child: RadioListTile<ConnectionMode>(
                                                title: Text('WebSocket', style: TextStyle(color: Colors.white, fontSize: 14)),
                                                subtitle: Text('Simpler setup', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                                value: ConnectionMode.websocket,
                                                groupValue: socialStreamConfig.mode,
                                                activeColor: Colors.purple,
                                                onChanged: (ConnectionMode? value) {
                                                  if (value != null) {
                                                    setState(() {
                                                      socialStreamConfig = SocialStreamConfig(
                                                        sessionId: socialStreamConfig.sessionId,
                                                        mode: value,
                                                        password: null,
                                                        enabled: socialStreamConfig.enabled,
                                                      );
                                                    });
                                                    _updateSettings();
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // WebRTC Password Input (only for WebRTC mode)
                                  if (socialStreamConfig.mode == ConnectionMode.webrtc) ...[
                                    SizedBox(height: 12),
                                    TextField(
                                      style: TextStyle(color: Colors.white),
                                      controller: _socialStreamPasswordController,
                                      onChanged: (String text) {
                                        setState(() {
                                          socialStreamConfig = SocialStreamConfig(
                                            sessionId: socialStreamConfig.sessionId,
                                            mode: socialStreamConfig.mode,
                                            password: text.isEmpty ? 'false' : text,
                                            enabled: socialStreamConfig.enabled,
                                          );
                                        });
                                        _updateSettings();
                                      },
                                      decoration: InputDecoration(
                                        hintText: "false",
                                        labelText: 'Encryption Password (optional)',
                                        helperText: 'Leave as "false" to disable encryption, or set a custom password',
                                        helperMaxLines: 2,
                                        helperStyle: TextStyle(color: Colors.white54),
                                        labelStyle: TextStyle(color: Colors.white70),
                                        hintStyle: TextStyle(color: Colors.white30),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Colors.purple),
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                          
                          // System Audio Toggle (Android only)
                          if (Platform.isAndroid && widget.currentDeviceID == "screen") ...[
                            SizedBox(height: 8),
                            Container(
                              margin: EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SwitchListTile(
                                title: const Text('Capture System Audio', style: TextStyle(color: Colors.white)),
                                subtitle: Text('Include device audio with screen share (Android 10+)', 
                                  style: TextStyle(color: Colors.white54, fontSize: 12)),
                                value: enableSystemAudio,
                                activeColor: ninjaAccentColor,
                                onChanged: (bool value) {
                                  setState(() {
                                    enableSystemAudio = value;
                                  });
                                  _updateSettings();
                                }
                              ),
                            ),
                          ],
                        ],
                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                
                // Bottom Action Buttons
                Container(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('CANCEL',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              )
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context, DialogDemoAction.cancel);
                          }
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('CONNECT',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              )
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ninjaAccentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context, DialogDemoAction.connect);
                          }
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String? _validateWSSAddress(String address) {
    if (address.isEmpty) return null;
    
    // Don't validate partial URLs during typing (less than 5 characters)
    if (address.length < 5) return null;
    
    try {
      // Try to normalize and then validate
      String normalizedAddress = _normalizeWSSAddress(address);
      Uri uri = Uri.parse(normalizedAddress);
      if (uri.host.isEmpty) {
        return 'Invalid URL format';
      }
      if (!['ws', 'wss'].contains(uri.scheme)) {
        return 'URL must use ws:// or wss:// protocol';
      }
    } catch (e) {
      return 'Invalid URL format';
    }
    
    return null;
  }
  
  String? _validateBitrate(int bitrate) {
    if (!useCustomBitrate || _customBitrateController.text.isEmpty) return null;
    
    if (bitrate < 100) {
      return 'Minimum bitrate is 100 kbps';
    }
    if (bitrate > 50000) {
      return 'Maximum bitrate is 50000 kbps';
    }
    
    return null;
  }
}

// Move WebViewScreen to top-level
class WebViewScreen extends StatefulWidget {
  final String url;
  WebViewScreen({required this.url});
  
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  Future<void> requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.granted) {} 
    else if (status == PermissionStatus.denied) {} 
    else if (status == PermissionStatus.permanentlyDenied) {}
  }
  
  late WebViewController controller;
  final PlatformWebViewControllerCreationParams params = const PlatformWebViewControllerCreationParams();
  
  @override
  void initState() {
    super.initState();
    controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) {
        request.grant();
      },
    )..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {
            print('Loading page');
          },
          onPageFinished: (String url) {},
        onWebResourceError: (WebResourceError error) {},
        onNavigationRequest: (NavigationRequest request) {
          return NavigationDecision.navigate;
        },
      ),
    )..loadRequest(Uri.parse(widget.url));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WebViewWidget(controller: controller),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(0.0),
        child: AppBar(),
      ),
    );
  }
}
