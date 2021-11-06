import 'dart:core';

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

void main() => runApp(new MyApp());

var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
Random _rnd = Random();

String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
    length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
var streamID = getRandomString(8);

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}



enum DialogDemoAction {
  cancel,
  connect,
}

class _MyAppState extends State<MyApp> {
  List<RouteItem> items;
  SharedPreferences _prefs;

  var _screenShare = "screen";
  List<Color> colors = [
    Color(0xFFA53E97),
    Color(0xFF645098),
    Color(0xFF33517E),
    Colors.amber,
    Colors.red,
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
          // subtitle: Text(item.subtitle),
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
          appBar: AppBar(
            title: Text('VDO.Ninja'),
          ),
          body: Stack(children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 10, 15),
                  child: Container(
                    width: double.infinity,
                    child: Text(
                      "Share",
                      textAlign: TextAlign.left,
                      style: theme.textTheme.headline1.apply(
                          color: Colors.white,
                          fontWeightDelta: 10,
                          fontSizeFactor: 1.5),
                    ),
                  ),
                ),
                ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      return _buildRow(context, items[i], i);
                    }),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: TextButton.icon(
                          icon: Icon(Icons.help_center),
                          style: Theme.of(context).elevatedButtonTheme.style,
                          onPressed: () => {_openDiscord()},
                          label: Text("Need help? Join our Discord.")),
                    ),
                  ],
                ),
              ],
            )
          ]
          )),
    );
  }

  _initData() async {
    _prefs = await SharedPreferences.getInstance();

    setState(() {
      Wakelock.enable();
      // You could also use Wakelock.toggle(on: true);
    });
	
	final androidConfig = FlutterBackgroundAndroidConfig(
		notificationTitle: "flutter_background example app",
		notificationText: "Background notification for keeping the example app running in the background",
		notificationImportance: AndroidNotificationImportance.Default,
		notificationIcon: AndroidResource(name: 'background_icon', defType: 'drawable'), // Default is ic_launcher from folder mipmap
	);
	bool success = await FlutterBackground.initialize(androidConfig: androidConfig);
  }

  void showDemoDialog<T>({BuildContext context, Widget child}) {
    showDialog<T>(
      context: context,
      builder: (BuildContext context) => child,
    ).then<void>((T value) {
      // The value passed to Navigator.pop() or null.
      if (value != null) {
        if (value == DialogDemoAction.connect) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (BuildContext context) => CallSample(
                      streamID: streamID, screenShare: _screenShare)));
        }
      }
    });
  }

  _showAddressDialog(context) {
    showDemoDialog<DialogDemoAction>(
        context: context,
        child: AlertDialog(
            title: const Text('Stream ID:'),
            content: TextField(
              onChanged: (String text) {
                setState(() {
                  streamID = text;
                });
              },
              decoration: InputDecoration(
                hintText: streamID,
              ),
              textAlign: TextAlign.center,
            ),
            actions: <Widget>[
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
    items = <RouteItem>[];

    items.add(RouteItem(
        title: 'SCREEN',
        subtitle: 'Share your device\'s screen',
        icon: Icons.screen_share,
        push: (BuildContext context) {
          _screenShare = "screen";
          _showAddressDialog(context);
        }));

    var devices = await navigator.mediaDevices.enumerateDevices();
    for (var item in devices) {
      if (item.kind != "videoinput") {
        continue;
      }

      var cameraType = "Camera";

      if (item.label.contains('back')) {
        cameraType = 'Back Camera';
      }

      if (item.label.contains('front')) {
        cameraType = 'Front Camera';
      }

      items.add(RouteItem(
          title: cameraType.toUpperCase(),
          subtitle:
              item.label.toString(),
          icon: item.label.contains('back')
              ? Icons.video_camera_back
              : Icons.video_camera_front,
          push: (BuildContext context) {
            _screenShare = item.deviceId;
            _showAddressDialog(context);
          }));
    }

    setState(() {});
  }

_openDiscord() async {
    const url = 'https://discord.vdo.ninja';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
}
}
