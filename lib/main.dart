// main.dart
import 'dart:core';
import 'package:flutter/foundation.dart'
show debugDefaultTargetPlatformOverride;
import 'package:vdo_ninja/theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'src/call_sample/call_sample.dart';
import 'src/route_item.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'dart:async'; 

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

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

  if (WebRTC.platformIsDesktop) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  } 
  
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Make the status bar transparent
    statusBarIconBrightness: Brightness.light, // Light icons for the status bar
    systemNavigationBarColor: Colors.black, // Navigation bar color
    systemNavigationBarIconBrightness: Brightness.light, // Light icons for the navigation bar
  ));

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(MyApp());
  }, (error, stackTrace) {
    print('Caught error: $error');
    print(stackTrace);
  });
}

Future<bool> startForegroundService() async {
    final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'VDO.Ninja background service',
        notificationText: 'VDO.Ninja background service',
        notificationImportance: AndroidNotificationImportance.Default,
        notificationIcon: AndroidResource(
            name: 'background_icon',
            defType: 'drawable',
        )
    );

    try {
        await FlutterBackground.initialize(androidConfig: androidConfig);
		await FlutterBackground.enableBackgroundExecution();
        return true;
    } catch (e) {
		try {
			await FlutterBackground.initialize(androidConfig: androidConfig);
			await FlutterBackground.enableBackgroundExecution();
			return true;
		} catch (e) {
			print('Error initializing FlutterBackground: $e');
		}
        return false;
    }
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
String WSSADDRESS = 'wss://wss.vdo.ninja:443';
String TURNSERVER = 'un;pw;turn:turn.x.co:3478';

String _selectedMicrophoneId = 'default';
List<MediaDeviceInfo> _microphones = [];

enum DialogDemoAction {
  cancel,
  connect,
}
class _MyAppState extends State < MyApp > {
  List < RouteItem > items = [];
  late SharedPreferences _prefs;
  var _deviceID = "screen";
  List < Color > colors = [
    Color(0xFFA53E97),
    Color(0xFF645098),
    Color(0xFF33517E),
    Colors.amber,
    Colors.red,
    Color(0xF133511E),
    Color(0xF233512E),
    Color(0xF333513E),
    Color(0xF433514E),
    Color(0xF533515E),
    Color(0xF633516E),
    Color(0xF733517E),
    Color(0xF833518E),
    Color(0xF933519E),
    Color(0xFF33510E),
    Color(0xFF33517E),
    Color(0xFF33517E),
    Color(0xFF33517E),
    Color(0xFF33517E),
    Color(0xFF33517E)
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
                    Align(
                      alignment: FractionalOffset.bottomCenter,
                      child: TextButton.icon(
                        icon: Icon(Icons.help_center),
                        style: Theme.of(context).elevatedButtonTheme.style,
                        onPressed: () => {
                          _openDiscord()
                        },
                        label: Text("Need help? Join our Discord.")),
                    ),
                  ],
                )),
            ],
          )),
      ),
    );
  }
  _initData() async {
	  
	if (WebRTC.platformIsAndroid) {
	   bool serviceStarted = await startForegroundService();
	   if (!serviceStarted) {
		 // Handle the failure appropriately
		 print('Failed to start foreground service');
	   }
	 }
	  
    _prefs = await SharedPreferences.getInstance();
	//await _prefs.clear();
	
    streamID = _prefs.getString('streamID') ?? "";
    roomID = _prefs.getString('roomID') ?? "";
    password = _prefs.getString('password') ?? "";
	
    WSSADDRESS = _prefs.getString('WSSADDRESS') ?? WSSADDRESS;
    TURNSERVER = _prefs.getString('TURNSERVER') ?? TURNSERVER;
	// _selectedMicrophoneId = _prefs.getString('audioDeviceId') ?? _selectedMicrophoneId;
	
    try {
      quality = _prefs.getBool('resolution') ?? false;
    } catch (e) {}
	
    try {
      landscape = _prefs.getBool('landscape') ?? false;
    } catch (e) {}
	
    if (streamID == "") {
		var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
		Random _rnd = Random();
		String getRandomString(int length) =>
		String.fromCharCodes(Iterable.generate(
		  length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
		streamID = getRandomString(8);
		_prefs.setString('streamID', streamID);

		if (_prefs.getString('password') == null){
		  _prefs.setString('password', password);
		}
    } else if (_prefs.getString('password') == null){
		password = "0";
		_prefs.setString('password', password);
	}
	
    streamID = streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    roomID = roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    setState(() {
      Wakelock.enable();
    });
	
    
  }

  void showDemoDialog<T>({
    required BuildContext context,
    required Widget child
  }) {
    showDialog < T > (
      context: context,
      builder: (BuildContext context) => child,
    ).then < void > ((T ? value) {
      if (value == DialogDemoAction.connect) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallSample(
              key: new GlobalKey < ScaffoldState > (),
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
              mirrored: true
            )));
      }
    });
  }
  _showAddressDialog(context) {
    showDemoDialog < DialogDemoAction > (
      context: context,
      child: AlertDialog(
          title: const Text('Publishing settings'),
          scrollable: true,
		  backgroundColor: theme.cardTheme.color,
		  surfaceTintColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          contentPadding: EdgeInsets.only(left: 10, right: 10, bottom: MediaQuery.of(context).viewInsets.bottom),
          content: SingleChildScrollView(
            child: new Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: TextField(
                      onChanged: (String text) {
                        setState(() {
                          streamID = text;
                          _prefs.setString('streamID', streamID);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: streamID,
                        labelText: 'Stream ID (auto-generated if empty)'
                      ),
                      textAlign: TextAlign.center
                    ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 55, 0, 0),
                    child: TextField(
                      controller: TextEditingController()..text = roomID ?? "",
                      onChanged: (String text) {
                        setState(() {
                          roomID = text;
                          _prefs.setString('roomID', roomID);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: roomID ?? "Room name",
                        labelText: 'Room name (optional)',
                      ),
                      textAlign: TextAlign.center,
                    ),
                ),
				Padding(
                  padding: const EdgeInsets.fromLTRB(0, 110, 0, 0),
                    child: TextField(
                      controller: TextEditingController()..text = password ?? "",
                      onChanged: (String textpass) {
                        setState(() {
                          password = textpass;
						  _prefs.setString('password', textpass);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: password ?? "Password",
                        labelText: 'Password (optional)',
                      ),
                      textAlign: TextAlign.center,
                    ),
                ),
				Padding(
				  padding: const EdgeInsets.fromLTRB(0, 190, 0, 0),
				  child: DropdownButton<String>(
					value: _selectedMicrophoneId,
					onChanged: (String? newValue) {
					  if (newValue != null) {
						_prefs.setString('audioDeviceId', newValue);
						setState(() {
						  _selectedMicrophoneId = newValue;
						  Navigator.pop(context);
						  _showAddressDialog(context);
						});
					  }
					},
					dropdownColor: Colors.grey[200], // Set the dropdown background color here
					items: _microphones.map<DropdownMenuItem<String>>((MediaDeviceInfo device) {
					  return DropdownMenuItem<String>(
						value: device.deviceId,
						child: Text(device.label),
					  );
					}).toList(),
				  ),
				),

                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 240, 0, 0),
                    child: SwitchListTile(
                      title: const Text('Prefer 1080p'),
                        value: quality,
                        onChanged: (bool value) {
                          _prefs.setBool('resolution', value);
                          setState(() {
                            quality = value;
                            Navigator.pop(context);
                            _showAddressDialog(context);
                          });
                        }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 280, 0, 0),
                    child: SwitchListTile(
                      title: const Text('Force landscape'),
                        value: landscape,
                        onChanged: (bool value) {
                          _prefs.setBool('landscape', value);
                          setState(() {
                            landscape = value;
                            Navigator.pop(context);
                            _showAddressDialog(context);
                          });
                        }
					),
                ),
                if (!advanced)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 320, 0, 0),
                      child: SwitchListTile(
                        title: const Text('Advanced'),
                          value: advanced,
                          onChanged: (bool value) {
                            _prefs.setBool('advanced', value);
                            setState(() {
                              advanced = value;
                              Navigator.pop(context);
                              _showAddressDialog(context);
                            });
                          }),
                  ),
                  if (advanced)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 320, 0, 0),
                        child: TextField(
                          onChanged: (String text) {
                            setState(() {
                              WSSADDRESS = text;
                              _prefs.setString('WSSADDRESS', WSSADDRESS);
                            });
                          },
                          decoration: InputDecoration(
                            hintText: WSSADDRESS,
                            labelText: 'Handshake server',
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ),
                    if (advanced)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 375, 0, 0),
                          child: TextField(
                            onChanged: (String text) {
                              setState(() {
                                TURNSERVER = text;
                                _prefs.setString('TURNSERVER', TURNSERVER);
                              });
                            },
                            decoration: InputDecoration(
                              hintText: TURNSERVER,
                              labelText: 'TURN server',
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ),
              ])),
          actions: < Widget > [
            TextButton(
              child: const Text('CANCEL'),
                onPressed: () {
                  Navigator.pop(context, DialogDemoAction.cancel);
                }),
            TextButton(
              child: const Text('CONNECT'),
                onPressed: () {
                  Navigator.pop(context, DialogDemoAction.connect);
                })
          ]));
  }
  _initItems() async {
	  
    items = < RouteItem > [];
	
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
	
    var devices = await navigator.mediaDevices.enumerateDevices();
	print(devices);

	
    for (var item in devices) {
      if (item.kind == "audioinput"){
		_microphones.insert(0, MediaDeviceInfo(deviceId: item.deviceId, label: item.label));
		print(item.deviceId);
		print(item.label);
		print(item);
		print("------------");
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
    items.add(RouteItem(
      title: 'WEB VERSION',
      subtitle: 'More features available',
      icon: Icons.grid_view,
      push: (BuildContext context) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => WebViewScreen(url: "https://vdo.ninja/?app=1")),
        );
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
  _openDiscord() async {
    final Uri url = Uri.parse('https://discord.vdo.ninja/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
      throw Exception('Could not launch $url');
    }
  }
}

final PlatformWebViewControllerCreationParams params =
  const PlatformWebViewControllerCreationParams();
class WebViewScreen extends StatefulWidget {
  final String url;
  WebViewScreen({
    required this.url
  });
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}
class _WebViewScreenState extends State < WebViewScreen > {
  Future < void > requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.granted) {} else if (status == PermissionStatus.denied) {} else if (status == PermissionStatus.permanentlyDenied) {}
  }
  late WebViewController controller;
  @override
  void initState() {
    super.initState();
    controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) {
        request.grant();
      },
    )..setJavaScriptMode(JavaScriptMode.unrestricted)..setBackgroundColor(const Color(0x00000000))..setNavigationDelegate(
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