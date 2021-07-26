import 'dart:core';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'src/call_sample/call_sample.dart';
import 'src/call_sample/data_channel_sample.dart';
import 'src/route_item.dart';

import 'dart:convert';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'src/utils/device_info.dart'
        if (dart.library.js) 'src/utils/device_info_web.dart';
		
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
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(item.title),
        onTap: () => item.push(context),
        trailing: Icon(Icons.arrow_right),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: Text('VDO.Ninja'),
          ),
          body: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return _buildRow(context, items[i]);
              })),
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
              FlatButton(
                  child: const Text('CANCEL'),
                  onPressed: () {
                    Navigator.pop(context, DialogDemoAction.cancel);
                  }),
              FlatButton(
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
			  title: 'Screen Share into VDO.Ninja',
			  subtitle: 'Screen Share.',
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
				  title: item.label.toString(),
				  subtitle: item.label.toString(),
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
