import 'dart:core';

import 'package:VDO.Ninja/theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'src/call_sample/call_sample.dart';
import 'src/route_item.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock/wakelock.dart';

void main() => runApp(new MyApp());

var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
Random _rnd = Random();

String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
var streamID =  getRandomString(8);


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
 
  
  @override
  initState() {
    super.initState();
    _initData();
    _initItems();
  }

  _buildRow(context, item) {
    return Card(
      child: ListTile(
        title: Text(item.title),
      subtitle: Text(item.subtitle),
      onTap: () => item.push(context),
        trailing: Icon(Icons.arrow_right),
        leading: Icon(
          item.icon,
          size: 40,
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
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 30, 10, 15),
                child: Container(
                  width: double.infinity,
                  child: Text(
                    "Share",
                    textAlign: TextAlign.left,
                    style: theme.textTheme.headline1.apply(color: Colors.white),
                  ),
                ),
              ),
              ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    return _buildRow(context, items[i]);
                  }),
            ],
          )),
    );
  }

  _initData() async {
    _prefs = await SharedPreferences.getInstance();
	
	setState(() {
		Wakelock.enable();
		// You could also use Wakelock.toggle(on: true);
	});
   
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
                  builder: (BuildContext context) => CallSample(streamID: streamID, screenShare: _screenShare)));
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
	
		items.add(
			RouteItem(
			  title: 'Screen',
        subtitle: 'Share your complete screen',
        icon: Icons.screen_share,
			  push: (BuildContext context) {
				_screenShare="screen";
				_showAddressDialog(context);
			  }
			)
		);
		
		var devices = await navigator.mediaDevices.enumerateDevices();
		for (var item in devices) {
			if (item.kind != "videoinput"){continue;}
			items.add(
				RouteItem(
				  title: item.label
              .toString()
              .replaceAllMapped(
                  RegExp(r'Camera (\d), '), (Match m) => "Camera ${m[1]} - ")
              .replaceAll(RegExp(r', Orientation \d{1,3}'), ""),
          subtitle:
              item.label.toString().replaceAll(RegExp(r'Camera \d, '), ''),
          icon: item.label.contains('back')
              ? Icons.video_camera_back
              : Icons.video_camera_front,
				  push: (BuildContext context) {
					_screenShare=item.deviceId;
					_showAddressDialog(context);
				  }
				)
			);
		}
		
		setState(() {});
			
  }
}
