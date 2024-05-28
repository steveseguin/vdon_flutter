import 'package:flutter/material.dart';
import 'dart:core';
import 'signaling.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:share/share.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

class CallSample extends StatefulWidget {
  static String tag = 'call_sample';

  final String streamID;
  final String deviceID;
  final String audioDeviceId;
  final String roomID;
  final String WSSADDRESS;
  final String TURNSERVER;
  final String password;
  final bool quality;
  final bool landscape;
  final bool preview;
  final bool muted;
  final bool mirrored;

  CallSample(
      {required Key key,
      required this.streamID,
      required this.deviceID,
	  required this.audioDeviceId,
      required this.roomID,
      required this.quality,
	  required this.landscape,
	  required this.WSSADDRESS,
	  required this.TURNSERVER,
	  required this.password,
      required this.preview,
      required this.muted,
      required this.mirrored})
      : super(key: key);

  @override
  _CallSampleState createState() => _CallSampleState();
}



class _CallSampleState extends State<CallSample> {
  late Signaling _signaling;
  List<dynamic> _peers = [];
  var _selfId = "";
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  bool muted = false;
  bool torch = false;
  bool preview = true;
  bool mirrored = true;
  double totalZoomLevel = 1.0;
  
  _CallSampleState();

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }
  

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
	_signaling.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
	
	SystemChrome.setPreferredOrientations([
		DeviceOrientation.landscapeRight,
		DeviceOrientation.landscapeLeft,
		DeviceOrientation.portraitUp,
		DeviceOrientation.portraitDown,
	  ]);
  }

  void _connect() async {
  
		if (widget.landscape){
			SystemChrome.setPreferredOrientations([
				  DeviceOrientation.landscapeRight,
				  DeviceOrientation.landscapeLeft,
			  ]);
		}
  
		 var TURNLIST = [
			  {'url': 'stun:stun.l.google.com:19302'},
			  {
				'url': 'turn:turn-use1.vdo.ninja:3478',
				'username': 'vdoninja',
				'credential': 'EastSideRepresentZ'
			  },
			  {
				'url': 'turns:www.turn.vdo.ninja:443',
				'username': 'vdoninja',
				'credential': 'IchBinSteveDerNinja'
			  }
		  ];
  
		if (widget.TURNSERVER=="" || widget.TURNSERVER == "un;pw;turn:turn.x.co:3478"){ // assume they are using the defaults
			  try {
				final uri = await Uri.parse("https://turnservers.vdo.ninja/?flutter="+DateTime.now().microsecondsSinceEpoch.toString());
				final response = await http.get(uri);
				print("-----------------------------------");
				if (response.statusCode == 200){
					var TURNLIST = jsonDecode(response.body)['servers'];
					TURNLIST.add({'url': 'stun:stun.l.google.com:19302'});
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				} else {
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				}
			  } on Exception catch (_) {
					print("using default hard coded turn list");
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
			  }
		  } else if (widget.TURNSERVER.startsWith("https://") || widget.TURNSERVER.startsWith("http://")){ // assume they are using the defaults
			  try {
				final uri = await Uri.parse(widget.TURNSERVER);
				final response = await http.get(uri); 
				if (response.statusCode == 200){
					var TURNLIST = jsonDecode(response.body)['servers'];
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				} else {
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				}
			  } on Exception catch (_) {
					print("using default hard coded turn list");
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
			  } 
		  } else {
				var customturn = widget.TURNSERVER.split(";");
				
				if (customturn.length==3){
					var TURNLIST  = [{'url': 'stun:stun.l.google.com:19302'}];
					TURNLIST.add({
						'url': customturn[2],
						'username': customturn[0],
						'credential': customturn[1]
					  });
					  _signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				} else if (customturn.length==1){
					
					if (customturn[0].startsWith("stun:")){
						var TURNLIST  = [{'url': customturn[0]}];
						_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
					} else if (customturn[0].startsWith("turn:")){
						var TURNLIST  = [{'url': 'stun:stun.l.google.com:19302'}];
						TURNLIST.add({
							'url': customturn[0]
						  });
						  _signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
					} else if (customturn[0].startsWith("turns:")){
						var TURNLIST  = [{'url': 'stun:stun.l.google.com:19302'}];
						TURNLIST.add({
							'url': customturn[0]
						  });
						  _signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
					} else if (customturn[0]=="false" || customturn[0]=="0" || customturn[0]=="off" || customturn[0]=="none"){
						var TURNLIST  = [{'url': 'stun:stun.l.google.com:19302'}];
						_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
					} else {
						var TURNLIST  = [{'url': 'stun:stun.l.google.com:19302'}];
						TURNLIST.add({
							'url': customturn[0]
						  });
						  _signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
					}
				} else{
					_signaling = await Signaling(widget.streamID, widget.deviceID, widget.audioDeviceId, widget.roomID, widget.quality, widget.WSSADDRESS, TURNLIST, widget.password);
				}
		  }
  
      _signaling.connect();

      _signaling.onSignalingStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling.onCallStateChange = (CallState state) {
        switch (state) {
          case CallState.CallStateNew:
            setState(() {
              _inCalling = true;
              _localRenderer.srcObject = _signaling.getLocalStream();
            });
            break;
          case CallState.CallStateBye:
            setState(() {
              _localRenderer.srcObject = null;
              _remoteRenderer.srcObject = null;
              _inCalling = false;
            });
            break;
          case CallState.CallStateInvite:
          case CallState.CallStateConnected:
          case CallState.CallStateRinging:
        }
      };

      _signaling.onPeersUpdate = ((event) {
        setState(() {
          _selfId = event['self'];
          _peers = event['peers'];
        });
      });

      _signaling.onLocalStream = ((stream) {
        print("LOCAL STREAM");
        _localRenderer.srcObject = stream;
        setState(() {});
      });

      _signaling.onAddRemoteStream = ((stream) {
        _remoteRenderer.srcObject = stream;
      });

      _signaling.onRemoveRemoteStream = ((stream) {
        _remoteRenderer.srcObject = null;
      });
    
  }

  _invitePeer(BuildContext context, String peerId, bool useScreen) async {
    if (peerId != _selfId) {
      _signaling.invite(peerId, 'video', useScreen);
    }
  }

  _hangUp() {
    _inCalling = false;

 _signaling.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
	
    Navigator.of(context).pop();
  }

  _switchCamera() {
    _signaling.switchCamera();
    
  }
  
  _zoomCamera(double zoomLevel) {
	  totalZoomLevel = totalZoomLevel-zoomLevel;
	  if (totalZoomLevel<1.0){
		  totalZoomLevel = 1.0;
	  } else if (totalZoomLevel>20.0){
		  totalZoomLevel = 20.0;
	  }
    _signaling.zoomCamera(totalZoomLevel);
  }

  _toggleFlashlight() async {
    setState(() {
      torch = !torch;
    });
    bool success = await _signaling.toggleTorch(torch);
    if (!success){
        setState(() {
          torch = false;
        });
    }
  }

  _toggleMic() {
    setState(() {
      muted = !muted;
    });
    _signaling.muteMic();
  }

  _togglePreview() {
    var status = false;

    print(_localRenderer.srcObject);
    if (_localRenderer.srcObject == null) {
      _localRenderer.srcObject = _signaling.getLocalStream();
      status = true;
    } else {
      _localRenderer.srcObject = null;
      status = false;
    }

    setState(() {
      preview = status;
    });
  }

  _toggleMirror() {
    setState(() {
      mirrored = !mirrored;
    });
  }

	_info() {
	  showDialog(
		context: context,
		builder: (BuildContext context) {
		  return Dialog(
			backgroundColor: Colors.transparent,
			child: Stack(
			  children: <Widget>[
				Positioned(
				  top: 50,
				  left: 20,
				  right: 20,
				  child: Material(
					color: Colors.white,
					borderRadius: BorderRadius.circular(8),
					child: Padding(
					  padding: const EdgeInsets.all(20.0),
					  child: Text(
						"&bitrate=6000 and &codec=av1 can be added to the viewer side's URL to increase quality.\n\nMore such options are listed at:\nhttps://docs.vdo.ninja",
						style: TextStyle(color: Colors.black),
					  ),
					),
				  ),
				),
			  ],
			),
		  );
		},
	  );
	}
	
  @override
  Widget build(BuildContext context) {

	String tmp = "https://vdo.ninja/?v=" + widget.streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
	

    if (widget.roomID != "") {
      tmp = "https://vdo.ninja/?v=" +
          widget.streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_') +
          "&r=" +
          widget.roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_') +
          "&scn";
    }
	if ((widget.password == "0") || (widget.password == "false") || (widget.password == "off") || (widget.password == "")){
		tmp += "&p=0";
	} else if (widget.password != "someEncryptionKey123"){
		tmp = "https://vdo.ninja/?v=" + widget.streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_') + "&p="+widget.password;
	}
	
	if ( widget.WSSADDRESS != 'wss://wss.vdo.ninja:443')
		tmp = tmp + "&wss=" + Uri.encodeComponent(widget.WSSADDRESS.replaceAll("wss://",""));
	
    final vdonLink = tmp;
    final key = new GlobalKey<ScaffoldState>();

	

    Widget callControls() {
      double buttonWidth = 60;
      List<Widget> buttons = [];

     /*  if (_microphones.length > 1) {
		  buttons.add(
			Stack(
			  alignment: Alignment.center,
			  children: [
				RawMaterialButton(
				  constraints: BoxConstraints(minWidth: buttonWidth),
				  visualDensity: VisualDensity.comfortable,
				  onPressed: () => {_toggleMic()},
				  fillColor: muted ? Colors.red : Colors.green,
				  child: muted ? Icon(Icons.mic_off) : Icon(Icons.mic),
				  shape: CircleBorder(),
				  elevation: 2,
				  padding: EdgeInsets.all(15),
				),
				Positioned(
				  top: -11, // Adjust this value as needed
				  right: -11, // Adjust this value as needed
				  child: Container(
					padding: EdgeInsets.only(top: 10, right: 10), // Add padding to prevent cropping
					child: PopupMenuButton<String>(
					  onSelected: (String newValue) {
						setState(() {
						  _selectedMicrophoneId = newValue;
						  _signaling.changeAudioSource(_selectedMicrophoneId);
						});
					  },
					  itemBuilder: (BuildContext context) {
						return _microphones.map((MediaDeviceInfo device) {
						  return PopupMenuItem<String>(
							value: device.deviceId,
							child: Text(device.label),
						  );
						}).toList();
					  },
					  child: Icon(Icons.arrow_drop_down_circle, color: Colors.white, size: 20), // Adjust size as needed
					),
				  ),
				),
			  ],
			),
		  );
		} else { */
		  // Add the original mute button if there's only one microphone source
		  buttons.add(
			RawMaterialButton(
			  constraints: BoxConstraints(minWidth: buttonWidth),
			  visualDensity: VisualDensity.comfortable,
			  onPressed: () => {_toggleMic()},
			  fillColor: muted ? Colors.red : Colors.green,
			  child: muted ? Icon(Icons.mic_off) : Icon(Icons.mic),
			  shape: CircleBorder(),
			  elevation: 2,
			  padding: EdgeInsets.all(15),
			),
		  );
		//}
	  

	  if (widget.deviceID == 'microphone') { 
		//
      } else if (widget.deviceID != 'screen') {
        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: () => {_togglePreview()},
          fillColor: preview ? Colors.green : Colors.red,
          child:
              preview ? Icon(Icons.personal_video) : Icon(Icons.play_disabled),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(15),
        ));

        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: () => {_switchCamera()},
          fillColor: preview ? Colors.green : Colors.red,
          child: Icon(Icons.cameraswitch),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(15),
        ));
		
        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: () => {_toggleMirror()},
          fillColor: preview ? Colors.green : Colors.red,
          child: Icon(Icons.compare_arrows),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(15),
        ));

        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: () => {_toggleFlashlight()},
          fillColor: !torch ? Colors.red : Colors.green,
          child: !torch ? Icon(Icons.flashlight_off) : Icon(Icons.flashlight_on),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(15),
        ));
      }

      buttons.add(RawMaterialButton(
        constraints: BoxConstraints(minWidth: buttonWidth),
        visualDensity: VisualDensity.comfortable,
        onPressed: () => {_hangUp()},
        fillColor: Colors.red,
        child: Icon(Icons.call_end),
        shape: CircleBorder(),
        elevation: 2,
        padding: EdgeInsets.all(15),
      ));

      return Padding(
        padding: const EdgeInsets.all(10.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: Container(
            color: Colors.black.withAlpha(100),
            child: SizedBox(
              height: 80,
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: buttons,
              ),
            ),
          ),
        ),
      );
    }

	return Scaffold(
      key: key,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(65.0),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 120,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                SizedBox(width: 2),
                IconButton(
                  icon: Icon(Icons.info),
                  color: Colors.white,
                  onPressed: () => _info(),
                ),
              ],
            ),
          ),
        ),
      ),
	  body: Center(
		child: Column(
		  mainAxisAlignment: MainAxisAlignment.start,
		  children: [
			Expanded(
			  child: Stack(
				alignment: Alignment.bottomCenter,
				children: [
				  widget.deviceID != 'screen'
					  ? widget.deviceID != 'microphone'
						  ? GestureDetector(
							  onVerticalDragUpdate: (details) {
								double delta = details.primaryDelta ?? 0.0;
								if (delta > 0) {
								  // User is swiping down, zoom out
								  _zoomCamera(0.04); // Adjust the zoom factor as needed
								} else if (delta < 0) {
								  // User is swiping up, zoom in
								  _zoomCamera(-0.04); // Adjust the zoom factor as needed
								}
							  },
							  child: RTCVideoView(
								_localRenderer,
								objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
								mirror: widget.deviceID == "rear" || widget.deviceID == "environment" || widget.deviceID.contains("0") ? !mirrored : mirrored
							  ),
							)
						  : Container(
							  color: Theme.of(context).canvasColor,
							  child: Column(
								mainAxisAlignment: MainAxisAlignment.center,
								crossAxisAlignment: CrossAxisAlignment.center,
								children: [
								  Padding(
									padding: const EdgeInsets.all(20.0),
									child: Text(
									  "Open the view link in a browser.  If it doesn't auto-play, click the page.",
									  textAlign: TextAlign.center,
									  style: TextStyle(
										  color: Colors.white, fontSize: 20),
									),
								  ),
								],
							  ),
							)
					  : Container(
						  color: Theme.of(context).canvasColor,
						  child: Column(
							mainAxisAlignment: MainAxisAlignment.center,
							crossAxisAlignment: CrossAxisAlignment.center,
							children: [
							  Padding(
								padding: const EdgeInsets.all(20.0),
								child: Text(
								  "Open the view link to see the screen's output. Permission to share the screen must be granted.",
								  textAlign: TextAlign.center,
								  style: TextStyle(
									  color: Colors.white, fontSize: 20),
								),
							  ),
							],
						  ),
						),
				  Positioned(
                    top: 65,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      color: Colors.black.withAlpha(100),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => Share.share(vdonLink),
                              child: Text(
                                "Open URL in OBS Browser Source:\n$vdonLink",
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  callControls(),
				],
			  ),
			),
		  ],
		),
	  ),
	  backgroundColor: const Color(0x000000ff),
	);
  }
}
