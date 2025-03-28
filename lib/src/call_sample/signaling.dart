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
import 'package:convert/convert.dart';
import 'package:permission_handler/permission_handler.dart';


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
        audioTrack.enabled = true;
        
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
  
  Future<void> handleConnectionTimeout(String sessionId, int timeoutMs) async {
	  // Store connection start time
	  final connectionStartTime = DateTime.now();
	  
	  // Create a timer to check connection status periodically
	  Timer.periodic(Duration(seconds: 30), (timer) {
		if (!active) {
		  timer.cancel();
		  return;
		}
		
		// Calculate time since connection started
		final timeElapsed = DateTime.now().difference(connectionStartTime).inMilliseconds;
		
		// Check if we've exceeded the timeout without establishing connection
		if (timeElapsed > timeoutMs && _sessions[sessionId] != null) {
		  final connectionState = _sessions[sessionId].connectionState;
		  
		  // If connection is not established or has failed, attempt reconnection
		  if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
			  connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
			
			print("Connection timeout detected for session $sessionId. Attempting reconnection...");
			
			// Clean up existing session
			_sessions[sessionId].close();
			_sessions.remove(sessionId);
			_sessionID.remove(sessionId);
			
			// Attempt to reconnect
			if (active) {
			  // Delay reconnection attempt to avoid rapid reconnection loops
			  Future.delayed(Duration(seconds: 2), () {
				if (active) {
				  connect();
				}
			  });
			}
			
			timer.cancel();
		  }
		}
	  });
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
	  try {
		// Track reconnection attempts to implement exponential backoff
		int reconnectionAttempt = 0;
		const int maxReconnectionAttempts = 5;
		
		// Function to attempt connection with retry logic
		Future<bool> attemptConnection() async {
		  try {
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
			  UUID = getRandomString(16);
			}
			
			_socket = SimpleWebSocket();
			
			// Set up socket handlers with improved error handling
			_socket.onOpen = () {
			  print('WebSocket connection established');
			  onSignalingStateChange.call(SignalingState.ConnectionOpen);
			  
			  // Reset reconnection attempts on successful connection
			  reconnectionAttempt = 0;
			  
			  try {
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
				  if (roomhashcode != "") {
					request["roomid"] = roomhashcode;
				  } else {
					request["roomid"] = roomID;
				  }
				  
				  if (!UUID.isEmpty) {
					request["from"] = UUID;
				  }
				  _socket.send(_encoder.convert(request));
				}
			  } catch (e) {
				print('Error sending initial requests: $e');
			  }
			};
			
			_socket.onMessage = (message) {
			  try {
				onMessage(_decoder.convert(message));
			  } catch (e) {
				print('Error processing message: $e');
			  }
			};
			
			_socket.onClose = (int code, String reason) {
			  print('WebSocket connection closed [$code => $reason]');
			  onSignalingStateChange.call(SignalingState.ConnectionClosed);
			  
			  if (active) {
				// Calculate exponential backoff delay
				int reconnectDelay = 1000 * pow(2, reconnectionAttempt).toInt();
				reconnectDelay = min(reconnectDelay, 30000); // Cap at 30 seconds
				
				if (reconnectionAttempt < maxReconnectionAttempts) {
				  print('Attempting reconnection #${reconnectionAttempt + 1} in ${reconnectDelay / 1000} seconds');
				  reconnectionAttempt++;
				  
				  Future.delayed(Duration(milliseconds: reconnectDelay), () {
					if (active) {
					  attemptConnection();
					}
				  });
				} else {
				  print('Max reconnection attempts reached. Giving up.');
				  // Notify application of permanent connection failure
				  onSignalingStateChange.call(SignalingState.ConnectionError);
				}
			  }
			};
			
			await _socket.connect(streamID + hashcode, WSSADDRESS, UUID);
			return true;
		  } catch (e) {
			print('Connection attempt failed: $e');
			return false;
		  }
		}
		
		// Initial connection attempt
		await attemptConnection();
		
		// Set up a connection timeout detector
		handleConnectionTimeout(UUID, 30000); // 30 second timeout
		
	  } catch (e) {
		print('Error in connect method: $e');
		active = false;
		onSignalingStateChange.call(SignalingState.ConnectionError);
	  }
	}

	Future<MediaStream> createStream(bool userScreen, String deviceID, String audioDeviceId) async {
	  try {
		String width = quality ? "1920" : "1280";
		String height = quality ? "1080" : "720";
		String framerate = quality ? "60" : "30";
		late MediaStream stream;
		
		// Improved error handling for media access
		Future<MediaStream?> safeMediaAccess(Future<MediaStream> Function() accessMethod, String accessType) async {
		  try {
			return await accessMethod();
		  } catch (e) {
			print('Error accessing $accessType: $e');
			
			// Check if the error is permission-related
			if (e.toString().contains('permission') || 
				e.toString().contains('denied') || 
				e.toString().contains('access')) {
			  print('Possible permission issue detected. Requesting permissions...');
			  
			  // Try requesting permissions explicitly
			  if (accessType.contains('camera')) {
				await Permission.camera.request();
			  }
			  if (accessType.contains('microphone')) {
				await Permission.microphone.request();
			  }
			  
			  // Try one more time after requesting permissions
			  try {
				return await accessMethod();
			  } catch (retryError) {
				print('Still failed after permission request: $retryError');
				return null;
			  }
			}
			return null;
		  }
		}
		
		Map<String, dynamic> getAudioConstraints(String audioDeviceId) {
		  return {
			'audio': {
			  if (audioDeviceId != "default") 'optional': {'sourceId': audioDeviceId},
			  'mandatory': {
				'googEchoCancellation': false,
				'echoCancellation': false,
				'noiseSuppression': false,
				'autoGainControl': false
			  }
			}
		  };
		}
		
		if (deviceID == "screen") {
		  // Screen sharing
		  MediaStream? displayStream = await safeMediaAccess(() => 
			navigator.mediaDevices.getDisplayMedia({
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
			}), 'screen');
		  
		  if (displayStream == null) {
			throw Exception('Failed to access screen sharing');
		  }
		  
		  stream = displayStream;
		  
		  // Add audio track separately with better error handling
		  try {
			MediaStream? audioStream = await safeMediaAccess(() => 
			  navigator.mediaDevices.getUserMedia(getAudioConstraints(audioDeviceId)),
			  'microphone');
			  
			if (audioStream != null && audioStream.getAudioTracks().isNotEmpty) {
			  await stream.addTrack(audioStream.getAudioTracks()[0]);
			}
		  } catch (e) {
			print('Error adding audio to screen share: $e');
			// Continue without audio track if it fails
		  }
		  
		} else if (deviceID == "microphone") {
		  // Audio-only mode
		  MediaStream? audioStream = await safeMediaAccess(() => 
			navigator.mediaDevices.getUserMedia({
			  'audio': audioDeviceId == "default"
				? {'mandatory': {'googEchoCancellation': false, 'echoCancellation': false}}
				: {
					'mandatory': {'googEchoCancellation': false, 'echoCancellation': false},
					'optional': [{'sourceId': audioDeviceId}]
				  },
			  'video': false
			}), 'microphone');
			
		  if (audioStream == null) {
			throw Exception('Failed to access microphone');
		  }
		  
		  stream = audioStream;
		  
		} else {
		  // Camera access
		  String facingMode;
		  if (deviceID == "front" || deviceID.contains("1") || deviceID == "user") {
			facingMode = 'user';
		  } else if (deviceID == "rear" || deviceID == "environment" || deviceID.contains("0")) {
			facingMode = 'environment';
		  } else {
			facingMode = '';
		  }
		  
		  Map<String, dynamic> constraints = {
			'audio': audioDeviceId == "default"
			  ? {'mandatory': {'googEchoCancellation': false, 'echoCancellation': false}}
			  : {
				  'optional': {'sourceId': audioDeviceId},
				  'mandatory': {'googEchoCancellation': false, 'echoCancellation': false}
				},
			'video': {
			  if (facingMode.isNotEmpty) 'facingMode': facingMode,
			  if (facingMode.isEmpty) 'deviceId': deviceID,
			  'mandatory': {
				'minWidth': width,
				'minHeight': height,
				'frameRate': framerate
			  }
			}
		  };
		  
		  MediaStream? cameraStream = await safeMediaAccess(() => 
			navigator.mediaDevices.getUserMedia(constraints),
			'camera and microphone');
			
		  if (cameraStream == null) {
			throw Exception('Failed to access camera and microphone');
		  }
		  
		  stream = cameraStream;
		}
		
		onLocalStream?.call(stream);
		
		return stream;
	  } catch (e) {
		print('Fatal error in createStream: $e');
		rethrow; // Let the caller handle this fatal error
	  }
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
	  
	  // Ensure iOS silent audio is properly disposed
	  if (Platform.isIOS) {
		_iosSilentAudio.dispose();
	  }
	  
	  // Add a try-catch to prevent crashes during cleanup
	  try {
		if (_localStream != null) {
		  final tracks = _localStream!.getTracks();
		  for (var track in tracks) {
			try {
			  await track.stop();
			} catch (e) {
			  print('Error stopping track: $e');
			}
		  }
		  await _localStream!.dispose();
		}

		// Close all sessions safely
		for (var entry in _sessions.entries) {
		  try {
			var request = Map();
			request["UUID"] = entry.key;
			request["bye"] = true;
			if (!UUID.isEmpty) {
			  request["from"] = UUID;
			}
			await _socket.send(_encoder.convert(request));
			await entry.value.close();
		  } catch (e) {
			print('Error closing session: $e');
		  }
		}

		// Close the websocket connection safely
		try {
		  await _socket.close();
		} catch (e) {
		  print('Error closing socket: $e');
		}
	  } catch (e) {
		print('Error in _cleanSessions: $e');
	  }
	}
}
