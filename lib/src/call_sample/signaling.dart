import 'dart:convert';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';
import 'dart:math';
import 'dart:core';
import 'dart:io' show Platform;
import 'package:tuple/tuple.dart';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';


enum SignalingState {
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

enum CallState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
}

/* Tuple2<String, IV> encryptMessage(String message,  {String? phrase}) {
  final phraseToUse = phrase ?? 'someEncryptionKey123vdo.ninja';
  final iv = IV.fromLength(16);

  final bytes1 = utf8.encode(phraseToUse);         // data being hashed
  final digest1 = sha256.convert(bytes1);  

  final key = Key.fromUtf8(digest1.toString());

  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

  final encrypted = encrypter.encrypt(message, iv: iv);
  final encryptedData = encrypted.base64;

  return  new Tuple2(encryptedData, iv);
}

Tuple2<String, IV> encryptMessage2(plainText) {
  final key = Key.fromUtf8('someEncryptionKey123vdo.ninja');
  final iv = IV.fromLength(16);

  final encrypter = Encrypter(AES(key));
  final encrypted = encrypter.encrypt(plainText, iv: iv); 

  print(encrypted.base64);

  return new Tuple2(encrypted.base64, iv);
}

String decryptMessage2(encrypted, iv) {
  final key = Key.fromUtf8('someEncryptionKey123vdo.ninja');
  final iv = IV.fromLength(16);

  final encrypter = Encrypter(AES(key));
  final decrypted = encrypter.decrypt(encrypted, iv: iv);

  return decrypted;
} */


/*
 * callbacks for Signaling API.
 */
typedef void CallStateCallback(CallState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);


class Signaling {
  var streamID = "";
  var deviceID = "screen";
  var roomID = "";
  var quality = false;
  var active = false;
  var WSSADDRESS = 'wss://wss.vdo.ninja:443';
  var UUID = "";
  var TURNLIST = [];

  Signaling (_streamID, _deviceID, _roomID, _quality, _WSSADDRESS, _TURNLIST) {
    // INIT CLASS

	_streamID = _streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
	_roomID = _roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');

    this.streamID = _streamID;
    this.deviceID = _deviceID;
    this.roomID = _roomID;
    this.quality = _quality;
	this.WSSADDRESS = _WSSADDRESS;
	this.TURNLIST = _TURNLIST;
	
	print("1111111111111111111111111111111111111111111111111111111111111111111111");
	print("1111111111111111111111111111111111111111111111111111111111111111111111");
	print("1111111111111111111111111111111111111111111111111111111111111111111111");
	print("1111111111111111111111111111111111111111111111111111111111111111111111");
	print(this.TURNLIST );

	
	if (this.WSSADDRESS != "wss://wss.vdo.ninja:443") {
	  var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
	  Random _rnd = Random();
	  String getRandomString(int length) =>
		  String.fromCharCodes(Iterable.generate(
			  length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
	  this.UUID = getRandomString(16);
	}
	
  }

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  late SimpleWebSocket _socket;
  var _port = 443;
  var _sessions = {};
  var _sessionID = {};


  late MediaStream _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  late Function(SignalingState state) onSignalingStateChange;
  late CallStateCallback onCallStateChange;
  late StreamStateCallback onLocalStream;
  late  StreamStateCallback onAddRemoteStream;
  late StreamStateCallback onRemoveRemoteStream;
  late OtherEventCallback onPeersUpdate;
  late DataChannelMessageCallback onDataChannelMessage;
  late  DataChannelCallback onDataChannel;

  String get sdpSemantics => 'unified-plan';
  
  
  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  close() async {
    _cleanSessions();
  }

  MediaStream getLocalStream() {
     return _localStream;
    
  }

  void switchCamera() {
      Helper.switchCamera(_localStream.getVideoTracks()[0]);
    
  }

  toggleTorch(torch) async {
      final videoTrack = _localStream
          .getVideoTracks()
          .firstWhere((track) => track.kind == "video");

      try {
        if (await videoTrack.hasTorch()) {
          await videoTrack.setTorch(torch);
          return true;
        } else {
          print("[TORCH] Current camera does not support torch mode");
        }
      } catch (e) {
        print("[TORCH] Current camera does not support torch mode 2");
      }
    
    return false;
  }

  void muteMic() {
      bool enabled = _localStream.getAudioTracks()[0].enabled;
      _localStream.getAudioTracks()[0].enabled = !enabled;
    
  }

  void invite(peerId, video, useScreen) {}

  void bye(peerId) {}

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;

    print(message);
	
	if (mapData.containsKey('from')){
		mapData['UUID'] = mapData['from'];
		if (mapData.containsKey("request") && (mapData['request'] == "play") && mapData.containsKey("streamID")){
			if (mapData['streamID'] == streamID){
				mapData['request'] = "offerSDP";
			} else {
				return;
			}
		}
		// mapData.removeWhere((key, value) => key == "from");
	}

    if (mapData['request'] == "offerSDP") {
      var uuid = mapData['UUID'];
	  
	   Map<String, dynamic> configuration = {
		'sdpSemantics': "unified-plan",
		'iceServers': this.TURNLIST
	  };

	  print("**************** configuration TO BE USED");
	  print(configuration);

      RTCPeerConnection pc = await createPeerConnection(configuration, _config);
      _sessionID[uuid] = new DateTime.now().toString();
      _sessions[uuid] = pc;
      

      pc.onTrack = (event) {
        if (event.track.kind == 'video') {
          onAddRemoteStream.call(event.streams[0]);
        }
      };

      _localStream.getTracks().forEach((track) {
        pc.addTrack(track, _localStream);
      });

      pc.onIceCandidate = (candidate) async {
        if (candidate == null) {
          print('onIceCandidate: complete!');
          return;
        }

        var request = Map();
        request["UUID"] = uuid;
        request["candidate"] = {
          // 'sdpMLineIndex': candidate.sdpMlineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate
        };
        request["type"] = "local";
        request["session"] = _sessionID[uuid];
        request["streamID"] = streamID;

        // request["roomID"] = roomID;
		if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
        _socket.send(_encoder.convert(request));
      };

      pc.onIceConnectionState = (state) {};

      _createOffer(uuid);
    } else if (mapData.containsKey('description')) {
      if (mapData['description']['type'] == "offer") {
        print("GOOD SO FAR OFFER GOT");
        await _sessions[mapData['UUID']].setRemoteDescription(
            RTCSessionDescription(
                mapData['description']['sdp'], mapData['description']['type']));
        //await _createAnswer(mapData['UUID']);

        //if (_sessions[mapData['UUID']].remoteCandidates.length > 0) {
        //	_sessions[mapData['UUID']].remoteCandidates.forEach((candidate) async {
        //		await _sessions[mapData['UUID']].addCandidate(candidate);
        //	});
        //	_sessions[mapData['UUID']].remoteCandidates.clear();
        //}
      } else {
        print("PROCESSING ANSWER - GOT ANSWER");
        _sessions[mapData['UUID']].setRemoteDescription(RTCSessionDescription(
            mapData['description']['sdp'], mapData['description']['type']));
      }
    } else if (mapData.containsKey('candidate')) {
      var candidateMap = mapData['candidate'];
      RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
          candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);

      if (_sessions[mapData['UUID']] != null) {
        await _sessions[mapData['UUID']].addCandidate(candidate);
      }
    } else if (mapData.containsKey('candidates')) {
      var candidateMap = mapData['candidates'];
      for (var i = 0; i < candidateMap.length; i++) {
        RTCIceCandidate candidate = RTCIceCandidate(
            candidateMap[i]['candidate'],
            candidateMap[i]['sdpMid'],
            candidateMap[i]['sdpMLineIndex']);
        print(candidateMap[i]);
        if (_sessions[mapData['UUID']] != null) {
          await _sessions[mapData['UUID']].addCandidate(candidate);
        }
      }
    }
  }

  Future<void> connect() async {
    _localStream = await createStream(true, deviceID);
    

    active=true;

	if (UUID.isEmpty && WSSADDRESS != "wss://wss.vdo.ninja:443") {
	  var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
	  Random _rnd = Random();
	  String getRandomString(int length) =>
		  String.fromCharCodes(Iterable.generate(
			  length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
	  UUID = getRandomString(16);
	}

    _socket = SimpleWebSocket();

    _socket.onOpen = () {
      print('onOpen');
      onSignalingStateChange.call(SignalingState.ConnectionOpen);

      var request = Map();
      request["request"] = "seed";
      request["streamID"] = streamID;
		
		if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
	     
      _socket.send(_encoder.convert(request));

      if (roomID != "") {
        var request = Map();
        request["request"] = "joinroom";
        request["roomid"] = roomID;
		
		if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
        _socket.send(_encoder.convert(request));
      }
    };

    _socket.onMessage = (message) {
      print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      onSignalingStateChange.call(SignalingState.ConnectionClosed);
      if (active==true){
	    UUID = "";
        _socket.connect(streamID, WSSADDRESS, UUID);
      }
    };

    await _socket.connect(streamID, WSSADDRESS, UUID);
  }

  Future<MediaStream> createStream(bool userScreen, String deviceID) async {

    String width = "1280";
    String height = "720";
    late MediaStream audioStream;
    late MediaStream stream;
    if (quality) {
      width = "1920";
      height = "1080";
    }
     String framerate = "60";

    if (deviceID == "screen") {
      if (Platform.isIOS){
        stream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'deviceId': 'broadcast'
          }, 
          'audio': true
        });
      } else {
         stream = await navigator.mediaDevices.getDisplayMedia({
          'video': true, 'audio': true
        });
      }
      if (stream.getAudioTracks().length == 0) {
        audioStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'mandatory': {
              'googEchoCancellation': false,
              'echoCancellation': false,
              'noiseSuppression': false,
              'autoGainControl': false
            }
          }
        });
        audioStream.getAudioTracks().forEach((element) async {
          await stream.addTrack(element);
        });
      }
    } else if (deviceID == "front" ||
        deviceID.contains("1") ||
        deviceID == "user") {
		if (quality){
        stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'facingMode': 'user',
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
          }
        }
      });
		} else{

			 stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'facingMode': 'user',
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
            'frameRate': framerate
          }
        }
      });
		}
	 } else if (deviceID == "microphone") {
       stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': false
        });
    } else if (deviceID == "rear" ||
        deviceID == "environment" ||
        deviceID.contains("0")) {
	if (quality){
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'facingMode': 'environment',
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
          }
        }
      });
    } else {
		stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'facingMode': 'environment',
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
            'frameRate': framerate
          }
        }
      });

	}
    } else {
      //var devices =  await navigator.mediaDevices.enumerateDevices();
      if (quality){
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {'googEchoCancellation': false, 'echoCancellation': false}
        },
        'video': {
          'deviceId': deviceID,
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
          }
        }
      });
	} else {
		stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {'googEchoCancellation': false, 'echoCancellation': false}
        },
        'video': {
          'deviceId': deviceID,
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
			'frameRate': framerate
          }
        }
      });
	}
    }
	
    onLocalStream?.call(stream);
    return stream;
  }

  void _addDataChannel(RTCDataChannel channel) {
    // channel.onDataChannelState = (e) {};
    //  channel.onMessage = (RTCDataChannelMessage data) {
    //     onDataChannelMessage?.call(channel, data);
    //  };
    //session.dc = channel; // need to add this to _sessions[] instead
    //  onDataChannel?.call(channel);
  }

  Future<void> _createDataChannel() async {
    // RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
    //     ..maxRetransmits = 30;
    //RTCDataChannel channel = await session.pc.createDataChannel(label, dataChannelDict);
    // _addDataChannel(session, channel);
  }

  Future<void> _createOffer(String uuid) async {
    print("CREATE OFFER");
    try {
      RTCSessionDescription s = await _sessions[uuid].createOffer(_dcConstraints);
      await _sessions[uuid].setLocalDescription(s);

      var request = Map();
      request["UUID"] = uuid;
      request["description"] = {'sdp': s.sdp, 'type': s.type};
      request["session"] = _sessionID[uuid];
      request["streamID"] = streamID;
	  if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
      _socket.send(_encoder.convert(request));
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _createAnswer(String uuid) async {
    try {
      RTCSessionDescription s = await _sessions[uuid].createAnswer({});
      await _sessions[uuid].setLocalDescription(s);

      var request = Map();
      request["UUID"] = uuid;
      request["description"] = {'sdp': s.sdp, 'type': s.type};
      request["session"] = _sessionID[uuid];
      request["streamID"] = streamID;
	  if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
      _socket.send(_encoder.convert(request));
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _cleanSessions() async {
    active=false;

    _localStream.getTracks().forEach((element) async {
      await element.stop();
    }); 
    await _localStream.dispose();
    _sessions.forEach((key, sess) async {
       var request = Map();
      request["UUID"] = key;
      request["bye"] = true;
	  if (!UUID.isEmpty){
		  request["from"] = UUID;
		}
      await _socket.send(_encoder.convert(request));
      await sess.close();
      //await sess.dispose();
    });

    // Close the websocket connection so the viewer doesn't auto-reconnect.
    _socket.close();
  }
}
