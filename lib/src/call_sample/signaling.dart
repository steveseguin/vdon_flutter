// signaling.dart
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
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_background/flutter_background.dart';
import 'package:convert/convert.dart';

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

String bytesToHex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String generateHash(String inputStr, [int? length]) {
  // Convert the input string to bytes
  List<int> inputBytes = utf8.encode(inputStr);

  // Calculate the SHA-256 hash of the input bytes
  Digest sha256Hash = sha256.convert(inputBytes);

  // If a length is provided, truncate the hash to that length
  if (length != null) {
    List<int> hashBytes = sha256Hash.bytes.sublist(0, length ~/ 2);
    return bytesToHex(hashBytes);
  } else {
    return bytesToHex(sha256Hash.bytes);
  }
}


class IosSilentAudioPlayer {
  MediaStream? _stream;
  bool _isActive = false;
  
  bool get isActive => _isActive;
  
  Future<MediaStream?> createSilentAudioStream() async {
    if (!Platform.isIOS) return null;
    
    final Map<String, dynamic> constraints = {
      'audio': {
        'mandatory': {
          'googNoiseSuppression': false,
          'googEchoCancellation': false,
          'googAutoGainControl': false,
          'googHighpassFilter': false,
          'googNoiseSuppression2': false,
          'googEchoCancellation2': false,
          'googAutoGainControl2': false
        },
        'optional': []
      },
    };

    try {
      _stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      final audioTrack = _stream?.getAudioTracks().first;
      if (audioTrack != null) {
        // Instead of setting volume, we enable/disable the track
        audioTrack.enabled = true;
        
        // Set track settings to minimize audio processing
        await audioTrack.applyConstraints({
          'autoGainControl': false,
          'noiseSuppression': false,
          'echoCancellation': false
        });
        
        _isActive = true;
      }
      
      return _stream;
    } catch (e) {
      print('Failed to create iOS silent audio stream: $e');
      _isActive = false;
      return null;
    }
  }

  void dispose() {
    if (_stream != null) {
      _stream?.getTracks().forEach((track) {
        track.enabled = false;
        track.stop();
      });
      _stream = null;
    }
    _isActive = false;
  }
}

// Add this as a class variable in your Signaling class
final _iosSilentAudio = IosSilentAudioPlayer();

/*
 * callbacks for Signaling API.
 */
typedef void CallStateCallback(CallState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Signaling {
  var streamID = "";
  var deviceID = "screen";
  var hashcode = "";
  var roomhashcode = "";
  var roomID = "";
  var quality = false;
  var active = false;
  var WSSADDRESS = 'wss://wss.vdo.ninja:443';
  var UUID = "";
  var TURNLIST = [];
  var audioDeviceId = "default";
  var salt = "vdo.ninja";
  var password = "someEncryptionKey123";
  var usepassword = true;
  MediaStream? _localStream;
  Signaling(_streamID, _deviceID, _audioDeviceId, _roomID, _quality,
      _WSSADDRESS, _TURNLIST, _password) {
    // INIT CLASS

    _streamID = _streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    _roomID = _roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');

    this.streamID = _streamID;
    this.deviceID = _deviceID;
    this.audioDeviceId = _audioDeviceId;
    this.roomID = _roomID;
    this.quality = _quality;
    this.WSSADDRESS = _WSSADDRESS;
    this.TURNLIST = _TURNLIST;

    if ((_password == "0") || (_password == "false") || (_password == "off")) {
      this.hashcode = "";
      this.password = "";
      this.roomhashcode = "";
      this.usepassword = false;
    } else if (_password != "") {
      this.hashcode = generateHash(_password + salt, 6);
      this.password = _password;
      if (_roomID != "") {
        this.roomhashcode = generateHash(_roomID + _password + salt, 16);
      }
    } else {
      this.hashcode = "";
      this.roomhashcode = "";
    }

    print("HASH CODE");
    print(this.hashcode);

    if (this.WSSADDRESS != "wss://wss.vdo.ninja:443") {
      var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
      Random _rnd = Random();
      String getRandomString(int length) =>
          String.fromCharCodes(Iterable.generate(
              length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
      this.UUID = getRandomString(16);
    }
  }
  Future<List<String>> encryptMessage(String message, [String? phrase]) async {
    phrase ??= password + salt;
    final key = _generateKey(phrase);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encryptedData = encrypter.encryptBytes(utf8.encode(message), iv: iv);
    return [hex.encode(encryptedData.bytes), hex.encode(iv.bytes)];
  }

  Future<String> decryptMessage(String hexEncryptedData, String hexIv,
      [String? phrase]) async {
    phrase ??= password + salt;
    final key = _generateKey(phrase);
    final iv = encrypt.IV(Uint8List.fromList(hex.decode(hexIv)));
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encryptedData =
        encrypt.Encrypted(Uint8List.fromList(hex.decode(hexEncryptedData)));
    final decryptedBytes = encrypter.decryptBytes(encryptedData, iv: iv);
    return utf8.decode(decryptedBytes); // Return the decrypted string
  }

  Uint8List convertStringToUint8Array(String str) {
    var bytes = Uint8List(str.length);
    for (var i = 0; i < str.length; i++) {
      bytes[i] = str.codeUnitAt(i);
    }
    return bytes;
  }

  encrypt.Key _generateKey(String phrase) {
    final Uint8List phraseBytes = convertStringToUint8Array(phrase);
    final digest = sha256.convert(phraseBytes);
    return encrypt.Key(
        Uint8List.fromList(digest.bytes)); // Convert List<int> to Uint8List
  }

  Future<void> changeAudioSource(String audioDeviceId) async {
    if (_localStream != null) {
      // Add null check
      final newLocalStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'optional': {'sourceId': audioDeviceId},
        },
        'video': false,
      });

      var newAudioTrack = newLocalStream.getAudioTracks()[0];

      for (var session in _sessions.values) {
        var senders = await session.getSenders();

        for (var sender in senders) {
          if (sender.track?.kind == 'audio') {
            await sender.replaceTrack(newAudioTrack);
          }
        }
      }

      if (_localStream!.getAudioTracks().isNotEmpty) {
        var oldAudioTrack = _localStream!.getAudioTracks()[0];
        if (oldAudioTrack != null) {
          _localStream!.removeTrack(oldAudioTrack);
          oldAudioTrack.stop();
        }
      }

      _localStream!.addTrack(newAudioTrack);
    }
  }

  Future<MediaStreamTrack> _createNewAudioTrack(String deviceId) async {
    final constraints = <String, dynamic>{
      'audio': {
        'deviceId': deviceId,
      },
    };
    print(constraints);
    final mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
    final audioTrack = mediaStream.getAudioTracks()[0];
    print("Selected audio track: ${audioTrack.label}");
    return audioTrack;
  }

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  late SimpleWebSocket _socket;
  var _port = 443;
  var _sessions = {};
  var _sessionID = {};

  List<MediaStream> _remoteStreams = <MediaStream>[];

  late Function(SignalingState state) onSignalingStateChange;
  late CallStateCallback onCallStateChange;
  late StreamStateCallback onLocalStream;
  late StreamStateCallback onAddRemoteStream;
  late StreamStateCallback onRemoveRemoteStream;
  late OtherEventCallback onPeersUpdate;
  late DataChannelMessageCallback onDataChannelMessage;
  late DataChannelCallback onDataChannel;

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
    if (_localStream != null) {
      return _localStream!;
    } else {
      // Handle the case where _localStream is null, e.g., by throwing an exception
      // or returning a dummy stream.
      throw Exception("Local stream not initialized");
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      // Add null check
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void zoomCamera(double zoomLevel) {
    if (_localStream != null) {
      // Add null check
      Helper.setZoom(_localStream!.getVideoTracks()[0], zoomLevel);
    }
  }

  toggleTorch(torch) async {
    if (_localStream != null) {
      // Add null check
      try {
        final videoTrack = _localStream!
            .getVideoTracks()
            .firstWhere((track) => track.kind == "video");
        if (await videoTrack.hasTorch()) {
          await videoTrack.setTorch(torch);
          return true;
        } else {
          print("[TORCH] Current camera does not support torch mode");
        }
      } catch (e) {
        print("[TORCH] Current camera does not support torch mode 2");
      }
    }
    return false;
  }

  void muteMic() {
    if (_localStream != null) {
      // Add null check
      bool enabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !enabled;
      print(_localStream!.getAudioTracks()[0].label);
    }
  }

  void invite(peerId, video, useScreen) {}

  void bye(peerId) {}

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;

    // print(message);

    if (mapData.containsKey('from')) {
      mapData['UUID'] = mapData['from'];
      if (mapData.containsKey("request") &&
          (mapData['request'] == "play") &&
          mapData.containsKey("streamID")) {
        if (mapData['streamID'] == streamID + hashcode) {
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

      print(configuration);

      RTCPeerConnection pc = await createPeerConnection(configuration, _config);
      _sessionID[uuid] = new DateTime.now().toString();
      _sessions[uuid] = pc;

      pc.onTrack = (event) {
        if (event.track.kind == 'video') {
          onAddRemoteStream.call(event.streams[0]);
        }
      };

      if (_localStream != null) {
        // Add null check
        _localStream!.getTracks().forEach((track) {
          pc.addTrack(track, _localStream!);
        });
      }

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
        request["streamID"] = streamID + hashcode;

        // request["roomID"] = roomID;
        if (!UUID.isEmpty) {
          request["from"] = UUID;
        }

        if (usepassword) {
          String candidateJson = jsonEncode(request["candidate"]);
          List<String> encrypted = await encryptMessage(candidateJson);
          request["candidate"] = encrypted[0];
          request["vector"] = encrypted[1];
        }

        _socket.send(jsonEncode(request));
      };

		pc.onIceConnectionState = (state) {
			print(state);
		};
		
		Future.delayed(Duration.zero, () {
		  _createOffer(uuid);
		});
	
    } else if (mapData.containsKey('description')) {
      if (usepassword && mapData.containsKey('vector')) {
        String decryptedJson =
            await decryptMessage(mapData['description'], mapData['vector']);
        mapData['description'] = jsonDecode(decryptedJson); // Decode JSON here
      }
      if (mapData['description']['type'] == "offer") {
        Future.delayed(Duration.zero, () async { 
		  try {
			await _sessions[mapData['UUID']].setRemoteDescription(
				RTCSessionDescription(mapData['description']['sdp'], mapData['description']['type'])
			);

			if (mapData['description']['type'] == "offer") {
			  _createAnswer(mapData['UUID']);
			} 
		  } catch (e) {
			print('Error setting remote description: ${e.toString()}');
		  }
		});
      } else {
        // This is an answer, schedule setRemoteDescription on the main thread
        Future.delayed(Duration.zero, () async {
          try {
            await _sessions[mapData['UUID']].setRemoteDescription(
                RTCSessionDescription(mapData['description']['sdp'],
                    mapData['description']['type']));
          } catch (e) {
            print('Error setting remote description: ${e.toString()}');
          }
        });
      }
    } else if (mapData.containsKey('candidate')) {
      if (usepassword && mapData.containsKey('vector')) {
        String decryptedJson =
            await decryptMessage(mapData['candidate'], mapData['vector']);
        mapData['candidate'] = jsonDecode(decryptedJson); // Decode JSON here
      }
      var candidateMap = mapData['candidate'];
      RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
          candidateMap['sdpMid'], null); // flutter no longer uses that?

      if (_sessions[mapData['UUID']] != null) {
        await _sessions[mapData['UUID']].addCandidate(candidate);
      }
    } else if (mapData.containsKey('candidates')) {
      if (usepassword && mapData.containsKey('vector')) {
        String decryptedJson =
            await decryptMessage(mapData['candidates'], mapData['vector']);
        mapData['candidates'] = jsonDecode(decryptedJson); // Decode JSON here
      }
      var candidateMap = mapData['candidates'];
      for (var i = 0; i < candidateMap.length; i++) {
        RTCIceCandidate candidate = RTCIceCandidate(
            candidateMap[i]['candidate'],
            candidateMap[i]['sdpMid'],
            candidateMap[i]['sdpMLineIndex']);
        // print(candidateMap[i]);
        if (_sessions[mapData['UUID']] != null) {
          await _sessions[mapData['UUID']].addCandidate(candidate);
        }
      }
    }
  }

  Future<void> connect() async {
    if (_localStream == null || _localStream!.getTracks().isEmpty) {
      _localStream = await createStream(true, deviceID, audioDeviceId);
    }

    active = true;

    if (UUID.isEmpty && (WSSADDRESS != "wss://wss.vdo.ninja:443")) {
      var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
      Random _rnd = Random();
      String getRandomString(int length) =>
          String.fromCharCodes(Iterable.generate(
              length, (_) => chars.codeUnitAt(_rnd.nextInt(chars.length))));
      UUID = getRandomString(16); // Generate UUID here
    }

    _socket = SimpleWebSocket();

    _socket.onOpen = () {
      print('onOpen');
      onSignalingStateChange.call(SignalingState.ConnectionOpen);

      var request = Map();
      request["request"] = "seed";
      request["streamID"] = streamID + hashcode;
      if (!UUID.isEmpty) {
        request["from"] = UUID;
      }
      _socket.send(_encoder.convert(request));

      if (roomID != "") {
        var request = Map();
        request["request"] = "joinroom";
        // return generateHash(roomid+session.password+session.salt+token,16).then(function(rid){
        if (roomhashcode != "") {
          request["roomid"] = roomhashcode;
        } else {
          request["roomid"] = roomID;
        }

        if (!UUID.isEmpty) {
          request["from"] = UUID;
        }
        print(request);
        _socket.send(_encoder.convert(request));
      }
    };

    _socket.onMessage = (message) {
      // print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      onSignalingStateChange.call(SignalingState.ConnectionClosed);
      if (active) {
        int reconnectAttempts = 0;
        int reconnectDelay = 1; // Initial delay in seconds
        const int maxReconnectAttempts = 5000; // Maximum reconnection attempts

        Timer.periodic(Duration(seconds: reconnectDelay), (timer) async {
          if (reconnectAttempts < maxReconnectAttempts) {
            print('Reconnecting attempt ${reconnectAttempts + 1}...');
            try {
              await _socket.connect(streamID + hashcode, WSSADDRESS, UUID);
              timer.cancel(); // Stop reconnection attempts if successful
            } catch (e) {
              print('Reconnection failed: ${e.toString()}');
              reconnectAttempts++;
              reconnectDelay *= 2; // Exponential backoff
              reconnectDelay =
                  min(reconnectDelay, 60); // Cap delay at 60 seconds
            }
          } else {
            print('Max reconnection attempts reached. Giving up.');
            timer.cancel();
          }
        });
      }
    };

    await _socket.connect(streamID + hashcode, WSSADDRESS, UUID);
  }

  Future<bool> startForegroundService() async {
    final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'VDO.Ninja background service',
        notificationText: 'VDO.Ninja background service',
        notificationImportance: AndroidNotificationImportance.Default,
        notificationIcon: AndroidResource(
          name: 'background_icon',
          defType: 'drawable',
        ));

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

  Future<MediaStream> createStream(
      bool userScreen, String deviceID, String audioDeviceId) async {
    String width = "1280";
    String height = "720";
    String framerate = "30";

    late MediaStream audioStream;
    late MediaStream stream;

    if (quality) {
      width = "1920";
      height = "1080";
      String framerate = "60";
    }

    print("AUDIO DEVICE");
    print(audioDeviceId);
    print(deviceID);

    if (WebRTC.platformIsAndroid) {
      bool serviceStarted = await startForegroundService();
      if (!serviceStarted) {
        // Handle the failure appropriately
        print('Failed to start foreground service');
      }
    }

    if (deviceID == "screen") {
    if (Platform.isIOS) {
      width = "1280";
      height = "720";
      
      try {
        // Get display media without audio first
        stream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'deviceId': 'broadcast',
            'mandatory': {
              'width': width,
              'height': height,
              'maxWidth': width,
              'maxHeight': width,
              'frameRate': framerate
            },
          },
        });

        // Add silent audio track only for iOS
        MediaStream? silentStream = await _iosSilentAudio.createSilentAudioStream();
        if (silentStream != null) {
          silentStream.getAudioTracks().forEach((track) async {
            await stream.addTrack(track);
          });
        }

        // Add selected microphone audio if specified
        if (audioDeviceId != "default") {
          MediaStream micStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
            }
          });
          micStream.getAudioTracks().forEach((track) async {
            await stream.addTrack(track);
          });
        }
      } catch (e) {
        print('Error setting up iOS screen sharing: $e');
        rethrow;
      }
    } else {
          try {
            stream = await navigator.mediaDevices.getDisplayMedia({
              'video': {
                'deviceId': 'broadcast',
                'mandatory': {
                  'width': width,
                  'height': height,
                  'maxWidth': width,
                  'maxHeight': width,
                  'frameRate': framerate
                },
                'width': width,
                'height': height,
                'maxWidth': width,
                'maxHeight': width,
                'frameRate': framerate
              },
              'audio': {
                'optional': {'sourceId': audioDeviceId},
              }
            });
          } catch (e) {
            print(e);
          }
        }
      } else if (audioDeviceId == "default") {
        width = "1280";
        height = "720";
        try {
          stream = await navigator.mediaDevices.getDisplayMedia({
            'video': {
              'deviceId': 'broadcast',
              'mandatory': {
                'width': width,
                'height': height,
                'maxWidth': width,
                'maxHeight': width,
                'frameRate': framerate
              },
              'width': width,
              'height': height,
              'maxWidth': width,
              'maxHeight': width,
              'frameRate': framerate
            },
            'audio': true
          });
        } catch (e) {
          print(e);
        }
      } else {
        width = "1280";
        height = "720";
        try {
          stream = await navigator.mediaDevices.getDisplayMedia({
            'video': {
              'deviceId': 'broadcast',
              'mandatory': {
                'width': width,
                'height': height,
                'maxWidth': width,
                'maxHeight': width,
                'frameRate': framerate
              },
              'width': width,
              'height': height,
              'maxWidth': width,
              'maxHeight': width,
              'frameRate': framerate
            },
            'audio': {
              'optional': {'sourceId': audioDeviceId},
            }
          });
        } catch (e) {
          print(e);
        }
      }
      if (stream.getAudioTracks().length == 0) {
        if (audioDeviceId == "default") {
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
        } else {
          audioStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
              'mandatory': {
                'googEchoCancellation': false,
                'echoCancellation': false,
                'noiseSuppression': false,
                'autoGainControl': false
              }
            }
          });
        }

        audioStream.getAudioTracks().forEach((element) async {
          await stream.addTrack(element);
        });
    } else if (deviceID == "front" ||
        deviceID.contains("1") ||
        deviceID == "user") {
      if (quality) {
        if (audioDeviceId == "default") {
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
        } else {
          stream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
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
        }
      } else {
        if (audioDeviceId == "default") {
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
        } else {
          stream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
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
          print({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
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
      }
    } else if (deviceID == "microphone") {
      if (audioDeviceId == "default") {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'mandatory': {
              'googEchoCancellation': false,
              'echoCancellation': false
            }
          },
          'video': false
        });
      } else {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            // 'deviceId': audioDeviceId,
            'mandatory': {},
            'optional': [
              {'sourceId': audioDeviceId.toString()}
            ],
          },
          'video': false
        });
        print("MIC ONLY");
        print({
          'audio': {
            // 'deviceId': audioDeviceId,
            'optional': [
              {'sourceId': audioDeviceId.toString()}
            ],
          },
          'video': false
        });
      }
    } else if (deviceID == "rear" ||
        deviceID == "environment" ||
        deviceID.contains("0")) {
      if (quality) {
        if (audioDeviceId == "default") {
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
              'optional': {'sourceId': audioDeviceId},
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
        }
      } else if (audioDeviceId == "default") {
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
      } else {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'optional': {'sourceId': audioDeviceId},
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
        print({
          'audio': {
            'optional': {'sourceId': audioDeviceId},
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
      if (quality) {
        if (audioDeviceId == "default") {
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
              }
            }
          });
        } else {
          stream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'optional': {'sourceId': audioDeviceId},
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
              }
            }
          });
        }
      } else if (audioDeviceId == "default") {
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
              'frameRate': framerate
            }
          }
        });
      } else {
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'optional': {'sourceId': audioDeviceId},
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
              'frameRate': framerate
            }
          }
        });
        print({
          'audio': {
            'optional': {'sourceId': audioDeviceId},
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
              'frameRate': framerate
            }
          }
        });
      }
    }
    print("Quality..");
    print(quality);
    print("deviceID...");
    print(deviceID);
    //var videoTrack = stream!.getVideoTracks().firstWhere((track) => track.kind == 'video');
    //if (videoTrack){
    //	WebRTC.invokeMethod('mediaStreamTrackSetZoom',<String, dynamic>{'trackId': videoTrack.id, 'zoomLevel': 1.0});
    //}

    onLocalStream?.call(stream);

    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      final audioTrack = audioTracks.first;
      print("Audio Track Label: ${audioTrack.label}");
    }

    return stream;
  }

  Future<void> _createDataChannel(RTCPeerConnection pc, String label) async {
//  RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
    //	..maxRetransmits = 30;
    //  RTCDataChannel channel = await pc.createDataChannel(label, dataChannelDict);
//  _addDataChannel(channel);
  }

  void _addDataChannel(RTCDataChannel channel) {
    //  channel.onDataChannelState = (state) {
    //	print('Data channel state changed: $state');
    //  };
    //  channel.onMessage = (RTCDataChannelMessage data) {
    //	onDataChannelMessage?.call(channel, data);
    //};
//  onDataChannel?.call(channel);
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
      request["session"] = _sessionID[uuid];
      request["streamID"] = streamID + hashcode;

      if (!UUID.isEmpty) {
        request["from"] = UUID;
      }

      if (usepassword) {
        List<String> encrypted =
            await encryptMessage(_encoder.convert(request["description"]));
        request["description"] = encrypted[0];
        request["vector"] = encrypted[1];
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
      request["streamID"] = streamID + hashcode;
      if (!UUID.isEmpty) {
        request["from"] = UUID;
      }

      if (usepassword) {
        List<String> encrypted =
            await encryptMessage(_encoder.convert(request["description"]));
        request["description"] = encrypted[0];
        request["vector"] = encrypted[1];
      }

      _socket.send(_encoder.convert(request));
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _cleanSessions() async {
    active = false;
    
      if (Platform.isIOS) {
        _iosSilentAudio.dispose();
    }
    if (_localStream != null) {
      // Add null check
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
    }

    _sessions.forEach((key, sess) async {
      var request = Map();
      request["UUID"] = key;
      request["bye"] = true;
      if (!UUID.isEmpty) {
        request["from"] = UUID;
      }
      await _socket.send(_encoder.convert(request));
      await sess.close();
    });

    // Close the websocket connection so the viewer doesn't auto-reconnect.
    await _socket.close();
  }
}
