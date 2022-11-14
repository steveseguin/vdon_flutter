import 'dart:convert';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/device_info.dart'
    if (dart.library.js) '../utils/device_info_web.dart';
import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';

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

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void CallStateCallback(CallState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Signaling {
  var streamID = "";
  var deviceID = "screen";
  var roomID = "";
  var quality = false;

  Signaling(_streamID, _deviceID, _roomID, _quality) {
    // INIT CLASS
    this.streamID = _streamID;
    this.deviceID = _deviceID;
    this.roomID = _roomID;
    this.quality = _quality;
  }

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  SimpleWebSocket _socket;
  var _port = 443;
  var _sessions = {};

  MediaStream _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  SignalingStateCallback onSignalingStateChange;
  CallStateCallback onCallStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  OtherEventCallback onPeersUpdate;
  DataChannelMessageCallback onDataChannelMessage;
  DataChannelCallback onDataChannel;

  String get sdpSemantics => 'unified-plan';

  Map<String, dynamic> configuration = {
    'sdpSemantics': "unified-plan",
    'iceServers': [
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
      },
    ]
  };

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
    _localStream = null;
    _remoteStreams = null;
  }

  MediaStream getLocalStream() {
    if (_localStream != null) {
      return _localStream;
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream.getVideoTracks()[0]);
    }
  }

  toggleTorch(torch) async {
    if (_localStream != null) {
      final videoTrack = _localStream.getVideoTracks().firstWhere((track) => track.kind == "video");

        try {
          if (await videoTrack.hasTorch()){
            await videoTrack.setTorch(torch);
            return true;
          } else {
             print("[TORCH] Current camera does not support torch mode");
          }
        } catch(e){
           print("[TORCH] Current camera does not support torch mode 2");
        }
    }
     return false;
  }

  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream.getAudioTracks()[0].enabled;
      _localStream.getAudioTracks()[0].enabled = !enabled;
    }
  }

  void invite(peerId, video, useScreen) {}

  void bye(peerId) {}

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;

    print(message);

    if (mapData['request'] == "offerSDP") {
      var uuid = mapData['UUID'];

      RTCPeerConnection pc = await createPeerConnection(configuration, _config);

      _sessions[uuid] = pc;

      pc.onTrack = (event) {
        if (event.track.kind == 'video') {
          onAddRemoteStream?.call(event.streams[0]);
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
        request["session"] = 'xxxx';
        request["streamID"] = streamID;
        // request["roomID"] = roomID;
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
    if (_localStream == null) {
      _localStream = await createStream(true, deviceID);
    } else {
      _sessions.forEach((key, sess) async {
        await sess.close();
      });
    }

    _socket = SimpleWebSocket();

    _socket.onOpen = () {
      print('onOpen');
      onSignalingStateChange?.call(SignalingState.ConnectionOpen);

      var request = Map();
      request["request"] = "seed";
      request["streamID"] = streamID;
      _socket.send(_encoder.convert(request));

      if (roomID != "") {
        var request = Map();
        request["request"] = "joinroom";
        request["roomid"] = roomID;
        _socket.send(_encoder.convert(request));
      }
    };

    _socket.onMessage = (message) {
      print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      onSignalingStateChange?.call(SignalingState.ConnectionClosed);
    };

    await _socket.connect(streamID);
  }

  Future<MediaStream> createStream(bool userScreen, String deviceID) async {
    MediaStream stream;

    String width = "1280";
    String height = "720";

    if (quality){
      width = "1920";
      height = "1080";
    }

    if (deviceID == "screen") {
      stream = await navigator.mediaDevices.getDisplayMedia({
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
            'minFrameRate': '60'
          }
        }
      });
      if (stream.getAudioTracks().length == 0) {
        MediaStream audioStream = await navigator.mediaDevices.getUserMedia({
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
            'minFrameRate': '60'
          }
        }
      });
    } else if (deviceID == "rear" ||
        deviceID == "environment" ||
        deviceID.contains("0")) {
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
            'minFrameRate': '60'
          }
        }
      });
    } else if (deviceID.startsWith("screen_")) {
      var cameraID = deviceID.split("screen_")[1];

      if (cameraID == "front" || deviceID.contains("1") || deviceID == "user") {
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
              'minFrameRate': '60'
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
            'deviceId': cameraID,
            'mandatory': {
              'minWidth': width,
              'minHeight': height,
              'minFrameRate': '60'
            }
          }
        });
      }
      MediaStream screenStream = await navigator.mediaDevices.getDisplayMedia({'audio': true, 'video': true});
      screenStream.getVideoTracks().forEach((element) async {
        await stream.addTrack(element);
      });
    } else {
      //var devices =  await navigator.mediaDevices.enumerateDevices();
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'deviceId': deviceID,
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
            'minFrameRate': '60'
          }
        }
      });
    }

    print({
        'audio': {
          'mandatory': {
            'googEchoCancellation': false,
            'echoCancellation': false
          }
        },
        'video': {
          'deviceId': deviceID,
          'mandatory': {
            'minWidth': width,
            'minHeight': height,
            'minFrameRate': '60'
          }
        }
      });

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

  Future<void> _createDataChannel({label: 'fileTransfer'}) async {
    // RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
    //     ..maxRetransmits = 30;
    //RTCDataChannel channel = await session.pc.createDataChannel(label, dataChannelDict);
    // _addDataChannel(session, channel);
  }

  Future<void> _createOffer(String uuid) async {
    print("CREATE OFFER");
    try {
      RTCSessionDescription s =
          await _sessions[uuid].createOffer(_dcConstraints);
      await _sessions[uuid].setLocalDescription(s);

      var request = Map();
      request["UUID"] = uuid;
      request["description"] = {'sdp': s.sdp, 'type': s.type};
      request["session"] = 'xxxx';
      request["streamID"] = streamID;
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
      request["session"] = 'xxxx';
      request["streamID"] = streamID;
      _socket.send(_encoder.convert(request));
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.close();
    });

    // Close the websocket connection so the viewer doesn't auto-reconnect.
    _socket.close();
  }
}
