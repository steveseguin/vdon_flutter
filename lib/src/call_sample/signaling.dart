// signaling.dart -- NEW , does not connect
import 'dart:convert';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// Conditional import for WebSocket (assuming '../utils/websocket.dart' exists for native)
import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';
import 'dart:math';
import 'dart:core';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:convert/convert.dart';
import 'package:permission_handler/permission_handler.dart';
// Import specific iOS audio configuration
import 'package:flutter_webrtc/src/native/ios/audio_configuration.dart';
// Import specific Android audio configuration (optional but good practice)
// import 'package:flutter_webrtc/src/native/android/audio_configuration.dart';
import 'package:flutter/services.dart';

// --- Enums and Helper Functions (Keep as is) ---
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
  List<int> inputBytes = utf8.encode(inputStr);
  Digest sha256Hash = sha256.convert(inputBytes);
  if (length != null) {
    List<int> hashBytes = sha256Hash.bytes.sublist(
        0,
        (length ~/ 2)
            .clamp(0, sha256Hash.bytes.length)); // Ensure length is valid
    return bytesToHex(hashBytes);
  } else {
    return bytesToHex(sha256Hash.bytes);
  }
}
// --- End Enums and Helper Functions ---

// --- iOS Silent Audio Player (Keep as is, crucial for background) ---
class IosSilentAudioPlayer {
  MediaStream? _stream;
  RTCPeerConnection? _pc; // Use a dummy PeerConnection
  bool _isActive = false;

  bool get isActive => _isActive;

  Future<void> createSilentAudioStream() async {
    if (!Platform.isIOS || _isActive) return;

    print("Creating iOS silent audio stream...");
    // Use minimal constraints, disabling processing is key
    final Map<String, dynamic> constraints = {
      'audio': {
        'mandatory': {
          'googNoiseSuppression': false, // Disable processing
          'googEchoCancellation': false,
          'googAutoGainControl': false,
          'googHighpassFilter': false,
          'googNoiseSuppression2': false,
          'googEchoCancellation2': false,
          'googAutoGainControl2': false,
          'noiseSuppression': false, // Standard names
          'echoCancellation': false,
          'autoGainControl': false,
        },
        'optional': [] // No specific device needed
      },
      'video': false
    };

    try {
      // 1. Get a silent audio track
      _stream = await navigator.mediaDevices.getUserMedia(constraints);
      final audioTrack = _stream?.getAudioTracks().first;

      if (audioTrack != null) {
        // 2. Create a dummy PeerConnection
        _pc = await createPeerConnection(
            {'iceServers': []}, {}); // No servers needed

        // 3. Add the track to the PeerConnection to keep it active
        await _pc!.addTrack(audioTrack, _stream!);

        // 4. Create an offer - this helps keep the audio session active
        // We don't need to send this offer anywhere.
        try {
          await _pc!.createOffer({});
          print("Dummy offer created for silent stream.");
        } catch (e) {
          print("Warning: Could not create dummy offer: $e");
        }

        audioTrack.enabled = true; // Ensure track is enabled
        _isActive = true;
        print('iOS silent audio stream is active.');
      } else {
        print('Failed to get silent audio track.');
        _isActive = false;
        dispose(); // Clean up if track failed
      }
    } catch (e) {
      print('ERROR creating iOS silent audio stream: $e');
      _isActive = false;
      dispose(); // Clean up on error
    }
  }

  void dispose() {
    print("Disposing iOS silent audio stream...");
    if (_stream != null) {
      _stream?.getTracks().forEach((track) {
        try {
          track.enabled = false; // Disable first
          track.stop(); // Then stop
        } catch (e) {
          print("Error stopping silent track: $e");
        }
      });
      _stream?.dispose();
      _stream = null;
    }
    if (_pc != null) {
      try {
        _pc!.close();
      } catch (e) {
        print("Error closing dummy peer connection: $e");
      }
      _pc = null;
    }
    _isActive = false;
    print("iOS silent audio stream disposed.");
  }
}
// --- End iOS Silent Audio Player ---


class CodecsHandler {
  static String setVideoBitrates(String sdp, Map<String, dynamic> params, [String? codec]) {
    var sdpLines = sdp.split('\r\n');
    final String maxBitrateStr = params['max'].toString();
    final String minBitrateStr = params['min'].toString();
    
    // Find the m line for video
    final mLineIndex = _findLine(sdpLines, 'm=', 'video');
    if (mLineIndex == null) {
      return sdp;
    }
    
    // Find appropriate codec payload
    String codecPayload = '';
    if (codec != null) {
      final codecIndex = _findLine(sdpLines, 'a=rtpmap', codec.toUpperCase()+'/90000');
      if (codecIndex != null) {
        codecPayload = _getCodecPayloadType(sdpLines[codecIndex]);
      }
    }
    
    // If no specific codec requested, use the first video codec
    if (codecPayload.isEmpty) {
      final videoMLine = sdpLines[mLineIndex];
      final pattern = RegExp(r'm=video\s\d+\s[A-Z/]+\s');
      final parts = videoMLine.split(pattern);
      if (parts.length > 1) {
        final sendPayloadType = parts[1].split(' ')[0];
        codecPayload = sendPayloadType;
      } else {
        // Handle SDP format variation
        final simplePattern = RegExp(r'm=video\s\d+\s\w+\s');
        final match = simplePattern.firstMatch(videoMLine);
        if (match != null) {
          final payloadSection = videoMLine.substring(match.end);
          codecPayload = payloadSection.trim().split(' ')[0];
        }
      }
    }
    
    // Add b=AS line for overall session bandwidth
    final asLineIndex = _findLine(sdpLines, 'b=AS:');
    if (asLineIndex != null) {
      // Update existing bandwidth line
      sdpLines[asLineIndex] = 'b=AS:$maxBitrateStr';
    } else {
      // Add new bandwidth line after m= line
      sdpLines.insert(mLineIndex + 1, 'b=AS:$maxBitrateStr');
      
      // Add TIAS bandwidth line as well (Transport Independent Application Specific)
      // TIAS is in bits per second, AS is in kilobits per second
      final tiasBitrate = (int.parse(maxBitrateStr) * 1000).toString();
      sdpLines.insert(mLineIndex + 2, 'b=TIAS:$tiasBitrate');
    }
    
    // Find the a=fmtp line for the codec and add bitrate parameters
    final fmtpLineIndex = _findLine(sdpLines, 'a=fmtp:$codecPayload');
    if (fmtpLineIndex != null) {
      String fmtpLine = sdpLines[fmtpLineIndex];
      // Check if we already have bitrate params
      if (!fmtpLine.contains('x-google-min-bitrate') && 
          !fmtpLine.contains('x-google-max-bitrate')) {
        
        final bitrates = 'x-google-min-bitrate=$minBitrateStr;x-google-max-bitrate=$maxBitrateStr';
        
        if (fmtpLine.contains(';')) {
          sdpLines[fmtpLineIndex] = fmtpLine + ';' + bitrates;
        } else {
          sdpLines[fmtpLineIndex] = fmtpLine + ' ' + bitrates;
        }
      }
    } else if (codecPayload.isNotEmpty) {
      // If no a=fmtp line exists, create one
      sdpLines.add('a=fmtp:$codecPayload x-google-min-bitrate=$minBitrateStr;x-google-max-bitrate=$maxBitrateStr');
    }
    
    return sdpLines.join('\r\n');
  }
  
  // Parse bitrate from incoming SDP
  static int? parseBitrateFromSdp(String sdp) {
    var sdpLines = sdp.split('\r\n');
    
    // First, check for b=AS: line (kilobits per second)
    final asLineIndex = _findLine(sdpLines, 'b=AS:');
    if (asLineIndex != null) {
      final asLine = sdpLines[asLineIndex];
      final match = RegExp(r'b=AS:(\d+)').firstMatch(asLine);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    
    // Check for b=TIAS: line (bits per second, convert to kbps)
    final tiasLineIndex = _findLine(sdpLines, 'b=TIAS:');
    if (tiasLineIndex != null) {
      final tiasLine = sdpLines[tiasLineIndex];
      final match = RegExp(r'b=TIAS:(\d+)').firstMatch(tiasLine);
      if (match != null) {
        final bitsPerSecond = int.tryParse(match.group(1)!);
        if (bitsPerSecond != null) {
          return bitsPerSecond ~/ 1000; // Convert to kbps
        }
      }
    }
    
    // Check for x-google-max-bitrate in fmtp lines
    for (var line in sdpLines) {
      if (line.startsWith('a=fmtp:')) {
        final match = RegExp(r'x-google-max-bitrate=(\d+)').firstMatch(line);
        if (match != null) {
          return int.tryParse(match.group(1)!);
        }
      }
    }
    
    return null;
  }
  
  // Helper method to find a line in SDP
  static int? _findLine(List<String> sdpLines, String prefix, [String? substr]) {
    for (int i = 0; i < sdpLines.length; i++) {
      if (sdpLines[i].startsWith(prefix)) {
        if (substr == null || sdpLines[i].toLowerCase().contains(substr.toLowerCase())) {
          return i;
        }
      }
    }
    return null;
  }
  
  // Helper to get codec payload type
  static String _getCodecPayloadType(String sdpLine) {
    final pattern = RegExp(r'a=rtpmap:(\d+) \w+\/\d+');
    final match = pattern.firstMatch(sdpLine);
    return match != null ? match.group(1)! : '';
  }
}


/*
 * Callbacks for Signaling API.
 */
typedef void CallStateCallback(CallState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Signaling {
  var streamID = "";
  var deviceID = "screen"; // Default or passed in
  var hashcode = "";
  var roomhashcode = "";
  var roomID = "";
  var quality = false; // Default or passed in
  var active = false;
  var WSSADDRESS = 'wss://wss.vdo.ninja:443'; // Default or passed in
  var UUID = "";
  var TURNLIST = []; // Default or passed in
  var audioDeviceId = "default"; // Default or passed in
  var salt = "vdo.ninja"; // Default salt, can be customized
  var password = ""; // Default or passed in
  var usepassword = false;
  MediaStream? _localStream;
  var _semaphores = <String, bool>{};
  // --- Add iOS Silent Audio Player instance ---
  final _iosSilentAudio = IosSilentAudioPlayer();
  var reconnectionAttempt = 0;
	final maxReconnectionAttempts = 5;
	final initialReconnectDelayMs = 1000;
	final maxReconnectDelayMs = 30000;
  
  // Connection timeout handling
  Timer? _connectionTimer;
  final connectionTimeoutMs = 30000; // 30 seconds for initial connection
  
  // Network quality monitoring
  Timer? _networkQualityTimer;
  Map<String, dynamic> _networkStats = {};
  final networkQualityIntervalMs = 5000; // Check every 5 seconds
  
  // Rate limiting for connection attempts
  Map<String, DateTime> _lastConnectionAttempts = {};
  final minConnectionIntervalMs = 2000; // Minimum 2 seconds between connection attempts
  
  // Bitrate settings
  var customBitrate = 0; // 0 means use default
  var sdpBitrate = 0; // Bitrate from SDP if any
  // -------------------------------------------

  // Constructor
  Signaling(
    String streamID,
    String deviceID,
    String audioDeviceId,
    String roomID,
    bool quality,
    String wssAddress,
    List turnList, // Expect List<Map<String, String>> or similar
    String password,
    int customBitrate,
    [String customSalt = 'vdo.ninja'] // Optional parameter with default value
  ) {
    // Sanitize IDs
    this.streamID = streamID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    this.roomID = roomID.replaceAll(RegExp('[^A-Za-z0-9]'), '_');

    this.deviceID = deviceID;
    this.audioDeviceId = audioDeviceId;
    this.quality = quality;
    this.WSSADDRESS = wssAddress;
    this.salt = customSalt;
    this.customBitrate = customBitrate;
    if (customBitrate > 0) {
      print("Custom bitrate set to ${customBitrate}kbps");
    }
    print("Using custom salt: ${this.salt}");
    this.TURNLIST = turnList.isNotEmpty
        ? turnList
        : [
            {'url': 'stun:stun.l.google.com:19302'}
          ]; // Ensure TURN list is not empty, provide default STUN
    this.password = password;

    // Password Handling - Fixed to properly handle password and hash generation
    if (password.isEmpty || ["0", "false", "off"].contains(password.toLowerCase())) {
      this.usepassword = false;
      this.hashcode = "";
      this.roomhashcode = "";
      print("Password protection disabled.");
    } else {
      this.usepassword = true;
      this.hashcode = generateHash(password + salt, 6);
      print("Password protection enabled. Stream Hash: ${this.hashcode}");
      if (this.roomID.isNotEmpty) {
        this.roomhashcode = generateHash(this.roomID + password + salt, 16);
        print("Room Hash: ${this.roomhashcode}");
      } else {
        this.roomhashcode = "";
      }
    }

    // Generate UUID if using custom WSS
    if (this.WSSADDRESS != 'wss://wss.vdo.ninja:443') {
      var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
      Random rnd = Random();
      this.UUID = String.fromCharCodes(Iterable.generate(
          16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      print("Using custom WSS. Generated UUID: ${this.UUID}");
    } else {
      this.UUID = ""; // No UUID needed for default WSS
    }
  }
Future<void> setFocusPoint(Point<double> point) async {
  if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
    final videoTrack = _localStream!.getVideoTracks()[0];
    try {
      print("Setting focus point: $point");
      await CameraUtils.setFocusPoint(videoTrack, point);
      
      print("Focus point set successfully");
    } catch (e) {
      print("Error setting focus point: $e");
    }
  }
}
Future<void> setExposurePoint(Point<double> point) async {
  if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
    final videoTrack = _localStream!.getVideoTracks()[0];
    try {
      print("Setting exposure point: $point");
      await CameraUtils.setExposurePoint(videoTrack, point);
      
      print("Exposure point set successfully");
    } catch (e) {
      print("Error setting exposure point: $e");
    }
  }
}
  // --- Encryption Methods (Keep as is) ---
  Future<List<String>> encryptMessage(String message, [String? phrase]) async {
    phrase ??= password + salt;
    if (phrase.isEmpty) return [message, ""]; // No encryption if no password

    final key = _generateKey(phrase);
    final iv = encrypt.IV.fromSecureRandom(16); // Use secure random IV
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encryptedData = encrypter.encryptBytes(utf8.encode(message), iv: iv);
    return [hex.encode(encryptedData.bytes), hex.encode(iv.bytes)];
  }

  Future<String> decryptMessage(String hexEncryptedData, String hexIv,
      [String? phrase]) async {
    phrase ??= password + salt;
    if (phrase.isEmpty || hexIv.isEmpty)
      return hexEncryptedData; // Cannot decrypt without phrase/IV

    try {
      final key = _generateKey(phrase);
      final iv = encrypt.IV(Uint8List.fromList(hex.decode(hexIv)));
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      final encryptedData =
          encrypt.Encrypted(Uint8List.fromList(hex.decode(hexEncryptedData)));
      final decryptedBytes = encrypter.decryptBytes(encryptedData, iv: iv);
      return utf8.decode(decryptedBytes);
    } catch (e) {
      print("Decryption failed: $e. Returning raw data.");
      // Consider how to handle decryption failures. Returning raw might expose encrypted data.
      // Maybe return an empty string or throw an error?
      return ""; // Or throw Exception("Decryption failed");
    }
  }

  Uint8List convertStringToUint8Array(String str) {
    // Using encode directly is generally preferred
    return utf8.encode(str) as Uint8List;
    /* var bytes = Uint8List(str.length);
    for (var i = 0; i < str.length; i++) {
      bytes[i] = str.codeUnitAt(i); // This might not handle multi-byte UTF-8 correctly
    }
    return bytes; */
  }

  encrypt.Key _generateKey(String phrase) {
    final Uint8List phraseBytes = convertStringToUint8Array(phrase);
    final digest = sha256.convert(phraseBytes);
    // Ensure key is 32 bytes (256 bits) for AES-256
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }
  // --- End Encryption Methods ---

  // --- iOS Audio Session Initialization ---
  Future<void> initializeIOSAudioSession({bool forScreenShare = false}) async {
    if (Platform.isIOS) {
      print("Initializing iOS Audio Session...");
      // Start the silent audio player to help keep the session active
      await _iosSilentAudio.createSilentAudioStream();

      // Configure audio session based on use case
      AppleAudioConfiguration config;
      if (forScreenShare) {
        print("Configuring for Screen Share (using videoRecording mode).");
        // This mode *might* help with system audio but often prioritizes mic.
        // System audio capture is heavily restricted on iOS.
        config = AppleAudioConfiguration(
          appleAudioCategory:
              AppleAudioCategory.playAndRecord, // Need record for mic
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.allowBluetooth,
            AppleAudioCategoryOption.mixWithOthers, // Allow mixing if possible
            // AppleAudioCategoryOption.allowAirPlay, // Optional
            AppleAudioCategoryOption
                .defaultToSpeaker, // Usually desired for screen share sound
          },
          appleAudioMode:
              AppleAudioMode.videoRecording, // Often used with ReplayKit
        );
      } else {
        print("Configuring for Camera/Mic (using voiceChat mode).");
        // Standard configuration for voice/video chat
        config = AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption
                .allowBluetooth, // Essential for BT headsets
            AppleAudioCategoryOption
                .mixWithOthers, // Allow background music etc.
            AppleAudioCategoryOption
                .defaultToSpeaker, // Default to speaker if no headset
          },
          appleAudioMode:
              AppleAudioMode.voiceChat, // Optimized for communication
        );
      }

      try {
        await AppleNativeAudioManagement.setAppleAudioConfiguration(config);
        print("iOS Audio Session configured successfully.");
      } catch (e) {
        print("ERROR setting iOS audio configuration: $e");
      }
    }
  }
  // --- End iOS Audio Session Initialization ---

// Replace the existing changeAudioSource method with this improved version
Future<void> changeAudioSource(String newAudioDeviceId) async {
  if (_localStream == null) {
    print("Cannot change audio source: Local stream not initialized.");
    return;
  }
  print("Attempting to change audio source to: $newAudioDeviceId");
  this.audioDeviceId = newAudioDeviceId; // Update the stored device ID

  try {
    // Create a dummy PeerConnection first to avoid the null reference
    RTCPeerConnection dummyPC = await createPeerConnection({
      'iceServers': [],
    }, {});
    
    // Get only the new audio track
    final newAudioStream = await navigator.mediaDevices.getUserMedia({
      'audio': audioDeviceId == "default"
          ? {
              'mandatory': {
                'googNoiseSuppression': true,
                'echoCancellation': false,
                'autoGainControl': true,
                'noiseSuppression': true,
                'googAutoGainControl': true,
                'googEchoCancellation': false,
              }
            }
          : {
              'optional': [
                {'sourceId': audioDeviceId}
              ],
              'mandatory': {
                'googNoiseSuppression': true,
                'echoCancellation': false,
                'autoGainControl': true,
                'noiseSuppression': true,
                'googAutoGainControl': true, 
                'googEchoCancellation': false,
              }
            },
      'video': false, // Important: only request audio
    });

    // Cleanup dummy PC
    await dummyPC.close();

    if (newAudioStream.getAudioTracks().isEmpty) {
      print("Error: Failed to get new audio track.");
      return;
    }
    var newAudioTrack = newAudioStream.getAudioTracks()[0];
    print("Got new audio track: ${newAudioTrack.label} (${newAudioTrack.id})");

    MediaStreamTrack? oldAudioTrack;
    if (_localStream!.getAudioTracks().isNotEmpty) {
      oldAudioTrack = _localStream!.getAudioTracks()[0];
      print("Found old audio track: ${oldAudioTrack.label} (${oldAudioTrack.id})");
    }

    // Replace the track in all active peer connections
    for (var session in _sessions.values) {
      var senders = await session.getSenders();
      for (var sender in senders) {
        if (sender.track?.kind == 'audio') {
          print("Replacing audio track in sender: ${sender.senderId}");
          await sender.replaceTrack(newAudioTrack);
        }
      }
    }

    // Update the local stream reference
    if (oldAudioTrack != null) {
      await _localStream!.removeTrack(oldAudioTrack);
      print("Removed old audio track from local stream.");
      // Stop the old track *after* removing it
      try {
        await oldAudioTrack.stop();
        print("Stopped old audio track.");
      } catch (e) {
        print("Error stopping old audio track: $e");
      }
    }

    await _localStream!.addTrack(newAudioTrack);
    print("Added new audio track to local stream.");
  } catch (e) {
    print("Error changing audio source: $e");
  }
}

  // Not currently used, changeAudioSource handles this. Keep for reference?
  Future<MediaStreamTrack> _createNewAudioTrack(String deviceId) async {
    final constraints = <String, dynamic>{
      'audio': deviceId == "default" ? true : {'deviceId': deviceId},
      'video': false,
    };
    print("Getting new audio track with constraints: $constraints");
    final mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
    final audioTrack = mediaStream.getAudioTracks()[0];
    print("Selected audio track: ${audioTrack.label}");
    return audioTrack;
  }
  // --- End Audio Source Change ---

  // --- Video Bitrate Control ---
  Future<void> setVideoBitrate(RTCPeerConnection pc, int targetBitrate) async {
    try {
      // Note: getParameters/setParameters may not be available in flutter_webrtc 0.13.0
      // We'll rely on SDP manipulation for now
      print("Bitrate control via RTCRtpSender not available in this version");
      print("Target bitrate ${targetBitrate}kbps will be applied via SDP manipulation");
      
      // Alternative approach: could try to renegotiate with new SDP
      // but that's more complex and may cause disruption
    } catch (e) {
      print("Error setting video bitrate: $e");
    }
  }

  int getTargetBitrate() {
    // Priority: SDP bitrate > custom bitrate > default based on quality
    if (sdpBitrate > 0) {
      return sdpBitrate;
    }
    
    if (customBitrate > 0) {
      return customBitrate;
    }
    
    // Default bitrates: 6mbps for 720p, 10mbps for 1080p
    return quality ? 10000 : 6000;
  }
  
  // --- End Video Bitrate Control ---

  // --- WebSocket and PeerConnection Management ---
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  late SimpleWebSocket _socket;
  bool _isSocketConnected = false;
  // var _port = 443; // Not used directly if WSSADDRESS includes port
  var _sessions = <String, RTCPeerConnection>{}; // Explicit type
  var _sessionID = <String, String>{}; // Explicit type

  List<MediaStream> _remoteStreams =
      <MediaStream>[]; // Keep if needed for remote streams

  // Callbacks
  late Function(SignalingState state) onSignalingStateChange;
  late CallStateCallback onCallStateChange;
  late StreamStateCallback onLocalStream;
  late StreamStateCallback onAddRemoteStream;
  late StreamStateCallback onRemoveRemoteStream;
  late OtherEventCallback onPeersUpdate;
  late DataChannelMessageCallback onDataChannelMessage;
  late DataChannelCallback onDataChannel;

  // WebRTC Config (Keep as is)
  String get sdpSemantics => 'unified-plan';
  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };
  // Offer/Answer Constraints
  final Map<String, dynamic> _sdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false, // Don't expect audio back by default
      'OfferToReceiveVideo': false, // Don't expect video back by default
    },
    'optional': [],
  };
  // Data Channel Constraints (Not used currently, keep for future)
  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {},
    'optional': [],
  };
  // --- End WebSocket and PeerConnection Management ---

  // --- Public Methods ---
  Future<void> close() async {
    print("Closing signaling connection and resources...");
    await _cleanSessions();
  }

  MediaStream? getLocalStream() {
    // Return potentially null stream
    return _localStream;
  }

  void switchCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      print("Switching camera...");
      // Helper.switchCamera expects the track
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    } else {
      print("Cannot switch camera: Video track not available.");
    }
  }

	void zoomCamera(double zoomLevel) {
	  if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
		try {
		  // Round to 2 decimal places to reduce unnecessary updates
		  final roundedZoom = (zoomLevel * 100).round() / 100;
		  print("Setting zoom level: $roundedZoom");
		  
		  final videoTrack = _localStream!.getVideoTracks()[0];
		  // Use a try-catch block to handle the IllegalStateException
		  try {
			CameraUtils.setZoom(videoTrack, roundedZoom);
		  } catch (e) {
			print("Error setting zoom: $e");
		  }
		} catch (e) {
		  print("Error accessing video track for zoom: $e");
		}
	  } else {
		print("Cannot zoom: Video track not available.");
	  }
	}

  Future<bool> toggleTorch(bool torch) async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks()[0];
      try {
        if (await videoTrack.hasTorch()) {
          print("Setting torch: $torch");
          await videoTrack.setTorch(torch);
          return true; // Success
        } else {
          print("[TORCH] Camera does not support torch mode.");
          return false; // Not supported
        }
      } catch (e) {
        print("[TORCH] Error accessing torch: $e");
        return false; // Error occurred
      }
    }
    print("[TORCH] Cannot toggle torch: Video track not available.");
    return false; // No track
  }
  
    // Helper to handle remote SDP descriptions
  Future<void> _handleRemoteDescription(String remoteUuid, Map mapData) async {
    var pc = _sessions[remoteUuid];
    if (pc == null) {
      print("Received description for unknown session: $remoteUuid. Ignoring.");
      return;
    }

    dynamic descriptionData = mapData['description'];
    Map descriptionMap;

    // Handle the case where description is a String or already a Map
    if (descriptionData is String) {
      // Decrypt if necessary
      if (usepassword && mapData.containsKey('vector')) {
        try {
          String decryptedJson =
              await decryptMessage(descriptionData, mapData['vector']);
          descriptionMap = _decoder
              .convert(decryptedJson); // Use _decoder instead of jsonDecode
          print("Decrypted remote description from $remoteUuid.");
        } catch (e) {
          print("Error decrypting description from $remoteUuid: $e. Aborting.");
          return;
        }
      } else {
        // Try to parse the string as JSON if it's not encrypted
        try {
          descriptionMap = _decoder
              .convert(descriptionData); // Use _decoder instead of jsonDecode
          print("Parsed string description as JSON from $remoteUuid.");
        } catch (e) {
          print(
              "Error parsing description string from $remoteUuid: $e. Aborting.");
          return;
        }
      }
    } else if (descriptionData is Map) {
      // Already a map, so we can use it directly
      descriptionMap = descriptionData;
    } else {
      print(
          "Invalid description format (neither String nor Map) from $remoteUuid. Ignoring.");
      return;
    }

    // Check if the descriptionMap has the required fields
    if (descriptionMap['sdp'] == null || descriptionMap['type'] == null) {
      print("Invalid description format received from $remoteUuid. Ignoring.");
      return;
    }

    String sdp = descriptionMap['sdp'];
    String type = descriptionMap['type'];
    
    // Parse bitrate from incoming SDP
    final parsedBitrate = CodecsHandler.parseBitrateFromSdp(sdp);
    if (parsedBitrate != null && parsedBitrate > 0) {
      print("Parsed bitrate from incoming SDP: ${parsedBitrate}kbps");
      sdpBitrate = parsedBitrate;
    }
    
    var description = RTCSessionDescription(sdp, type);

    print("Setting remote description ($type) for $remoteUuid.");

    try {
      await pc.setRemoteDescription(description);
      print("Remote description set successfully for $remoteUuid.");

      // If it was an offer, create and send an answer
      if (type == 'offer') {
        print("Received offer from $remoteUuid. Creating answer...");
        await _createAnswer(remoteUuid, _sessionID[remoteUuid]!, pc);
      } else {
        // It was an answer
        print("Received answer from $remoteUuid.");
        
        // If we parsed bitrate from the answer and we're sending video, apply it
        if (parsedBitrate != null && parsedBitrate > 0 && 
            _localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
          print("Applying parsed bitrate ${parsedBitrate}kbps from answer to our video sender");
          await setVideoBitrate(pc, parsedBitrate);
        }
      }
    } catch (e) {
      print("ERROR setting remote description for $remoteUuid: $e");
      // Handle error, maybe close connection?
      _handleBye(remoteUuid);
    }
  }
  
  
// Helper to properly clean up a peer connection
void _cleanupPeerConnection(String remoteUuid) {
  final pc = _sessions.remove(remoteUuid);
  _sessionID.remove(remoteUuid);
  
  if (pc != null) {
    try {
      pc.close();
      print("Cleaned up PeerConnection for $remoteUuid");
    } catch (e) {
      print("Error closing PeerConnection for $remoteUuid: $e");
    }
  }
}

  void muteMic() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      bool currentMuteStatus = !_localStream!.getAudioTracks()[0].enabled;
      bool newEnabledStatus = currentMuteStatus; // enabled = !muted
      _localStream!.getAudioTracks()[0].enabled = newEnabledStatus;
      print("Mic enabled: $newEnabledStatus (Muted: ${!newEnabledStatus})");
    } else {
      print("Cannot mute/unmute mic: Audio track not available.");
    }
  }

  void toggleVideoMute() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      bool currentMuteStatus = !_localStream!.getVideoTracks()[0].enabled;
      bool newEnabledStatus = currentMuteStatus; // enabled = !muted
      _localStream!.getVideoTracks()[0].enabled = newEnabledStatus;
      print("Video enabled: $newEnabledStatus (Muted: ${!newEnabledStatus})");
    } else {
      print("Cannot mute/unmute video: Video track not available.");
    }
  }

  // Invite/Bye methods not implemented in provided code, keep as stubs if needed
  void invite(peerId, video, useScreen) {
    print("Invite function called (Not implemented in detail). Peer: $peerId");
  }

  void bye(peerId) {
    print("Bye function called (Not implemented in detail). Peer: $peerId");
    // You might want to close the specific peer connection here
    if (_sessions.containsKey(peerId)) {
      print("Closing connection to peer: $peerId");
      _sessions[peerId]?.close();
      _sessions.remove(peerId);
      _sessionID.remove(peerId);
    }
  }
  // --- End Public Methods ---

  // --- WebSocket Message Handling ---
  void onMessage(message) async {
    // print("Raw WebSocket message received: $message"); // Debug raw message
    Map<String, dynamic> mapData;
    try {
      // Ensure message is decoded correctly
      if (message is String) {
        mapData = _decoder.convert(message);
      } else if (message is Map) {
        mapData =
            Map<String, dynamic>.from(message); // Handle if already decoded map
      } else {
        print("Unknown message format received: ${message.runtimeType}");
        return;
      }
    } catch (e) {
      print("Error decoding WebSocket message: $e");
      return;
    }

    // print("Decoded WebSocket message: $mapData"); // Debug decoded message

    // --- Request Handling Logic (Simplified VDO.Ninja protocol) ---
    String? requestType;
    String? uuid; // Remote peer's UUID

    // Handle 'from' field for UUID identification
    if (mapData.containsKey('from')) {
      uuid = mapData['from'] as String?;
      // Keep 'from' for context if needed, or remove if creates issues
      // mapData['UUID'] = uuid; // Standardize on UUID key if preferred
    } else if (mapData.containsKey('UUID')) {
      uuid = mapData['UUID'] as String?;
    }

    if (uuid == null || uuid.isEmpty) {
      // print("Warning: Received message without 'from' or 'UUID'. Ignoring.");
      // Some messages might not have UUID (e.g., initial server messages)
      // Handle based on message content if needed
      if (mapData.containsKey('error')) {
        print("Server Error Message: ${mapData['error']}");
      }
      // Handle other non-UUID messages if necessary
      return;
    }

    // Determine Request Type
    if (mapData.containsKey('request')) {
      requestType = mapData['request'] as String?;
      // Special handling for VDO.Ninja's 'play' request -> map to 'offerSDP'
      if (requestType == "play" && mapData.containsKey("streamID")) {
        // Verify stream ID matches the expected format (streamID + optional hashcode)
        if (mapData['streamID'] == streamID + hashcode) {
          requestType = "offerSDP"; // Treat 'play' request as an offer request
          print(
              "Received 'play' request for matching streamID, treating as offerSDP from $uuid");
        } else {
          print(
              "Received 'play' request for non-matching streamID (${mapData['streamID']}). Ignoring.");
          return; // Ignore if streamID doesn't match
        }
      }
    } else if (mapData.containsKey('description')) {
      requestType = "description";
    } else if (mapData.containsKey('candidate') ||
        mapData.containsKey('candidates')) {
      requestType = "candidate";
    } else if (mapData.containsKey('bye')) {
      requestType = "bye";
    }
    // Add other request types if needed

    // Process based on request type
    switch (requestType) {
      case "offerSDP": // Viewer wants to connect, create PC and send offer
        if (_sessions.containsKey(uuid)) {
          print(
              "Session already exists for $uuid. Ignoring new offerSDP request.");
          // Optional: Maybe close existing session and create new one?
          return;
        }
        print("Received offerSDP request from: $uuid");
        await _createPeerConnectionAndOffer(uuid);
        break;

      case "description": // Received SDP (offer or answer)
        print("Received SDP description from: $uuid");
        await _handleRemoteDescription(uuid, mapData);
        break;

      case "candidate": // Received ICE candidate(s)
        // print("Received ICE candidate(s) from: $uuid"); // Can be noisy
        await _handleRemoteCandidate(uuid, mapData);
        break;

      case "bye": // Peer disconnected
        print("Received 'bye' from: $uuid");
        _handleBye(uuid);
        break;

      default:
        print("Received unknown message type or request from $uuid: $mapData");
        break;
    }
  }


void _setPeerConnectionHandlers(RTCPeerConnection pc, String remoteUuid, String sessionId) {
  // ICE candidate handler
  pc.onIceCandidate = (candidate) async {
    if (candidate == null) {
      print("ICE gathering complete for $remoteUuid");
      return;
    }
    
    try {
      await _sendIceCandidate(remoteUuid, sessionId, candidate);
    } catch (e) {
      print("Error sending ICE candidate: $e");
    }
  };
  
  // Connection state tracking
  pc.onIceConnectionState = (state) {
    print("ICE connection state for $remoteUuid: $state");
    if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _handleConnectionError(remoteUuid, "ICE connection failed");
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      // Give some time for reconnection before triggering error recovery
      Future.delayed(Duration(seconds: 5), () {
        if (_sessions.containsKey(remoteUuid)) {
          final currentState = _sessions[remoteUuid]?.iceConnectionState;
          if (currentState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              currentState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            _handleConnectionError(remoteUuid, "ICE connection disconnected timeout");
          }
        }
      });
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      _cleanupPeerConnection(remoteUuid);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
      // Reset reconnection attempt counter on successful connection
      reconnectionAttempt = 0;
      print("ICE connection established with $remoteUuid");
    }
  };
  
  pc.onConnectionState = (state) {
    print("PC connection state for $remoteUuid: $state");
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _handleConnectionError(remoteUuid, "Peer connection failed");
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      // Give some time for reconnection before triggering error recovery
      Future.delayed(Duration(seconds: 3), () {
        if (_sessions.containsKey(remoteUuid)) {
          final currentState = _sessions[remoteUuid]?.connectionState;
          if (currentState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              currentState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _handleConnectionError(remoteUuid, "Peer connection disconnected timeout");
          }
        }
      });
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      _cleanupPeerConnection(remoteUuid);
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      // Reset reconnection attempt counter on successful connection
      reconnectionAttempt = 0;
      print("Peer connection established with $remoteUuid");
      onCallStateChange?.call(CallState.CallStateConnected);
      
      // Start network quality monitoring for this connection
      _startNetworkQualityMonitoring(remoteUuid);
    }
  };
  
  // Media handlers
  pc.onTrack = (event) {
    if (event.track.kind == 'video' && event.streams.isNotEmpty) {
      print("Received video track from $remoteUuid");
      onAddRemoteStream?.call(event.streams[0]);
    }
  };
  
  pc.onRemoveTrack = (stream, track) {
    print("Track ${track.kind} removed from $remoteUuid");
  };
  
  // Data channel handler
  pc.onDataChannel = (channel) {
    print("Data channel received from $remoteUuid: ${channel.label}");
    _addDataChannel(channel);
    onDataChannel?.call(channel);
  };
}
Future<void> _createPeerConnectionAndOffer(String remoteUuid) async {
  // Prevent duplicate connection attempts
  if (_sessions.containsKey(remoteUuid)) {
    print("DEBUG: Session already exists for $remoteUuid, ignoring duplicate request");
    return;
  }
  
  // Rate limiting check
  final now = DateTime.now();
  final lastAttempt = _lastConnectionAttempts[remoteUuid];
  if (lastAttempt != null) {
    final timeSinceLastAttempt = now.difference(lastAttempt).inMilliseconds;
    if (timeSinceLastAttempt < minConnectionIntervalMs) {
      print("DEBUG: Rate limiting connection attempt for $remoteUuid. Time since last: ${timeSinceLastAttempt}ms");
      return;
    }
  }
  
  _lastConnectionAttempts[remoteUuid] = now;
  
  print("DEBUG: Creating PeerConnection for $remoteUuid");
  
  // Generate session ID
  var sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  _sessionID[remoteUuid] = sessionId;
  print("DEBUG: Session ID created: $sessionId");
  
  try {
    // Configure ice servers
    Map<String, dynamic> configuration = {
      'sdpSemantics': sdpSemantics,
      'iceServers': this.TURNLIST
    };
    print("DEBUG: ICE server configuration: ${jsonEncode(configuration)}");
    
    // Create the peer connection
    print("DEBUG: Calling createPeerConnection...");
    RTCPeerConnection pc = await createPeerConnection(configuration, _config);
    print("DEBUG: createPeerConnection returned successfully");
    
    // Store the peer connection immediately
    _sessions[remoteUuid] = pc;
    print("DEBUG: PeerConnection stored in _sessions map");
    
    // Set up all event handlers BEFORE adding tracks
    // This is crucial - use our handler method to set up all callbacks
    _setPeerConnectionHandlers(pc, remoteUuid, sessionId);
    print("DEBUG: Event handlers set up for peer connection");
    
    // Check if we have a local stream
    if (_localStream == null) {
      print("WARNING: No local stream available for $remoteUuid");
    } else {
      print("DEBUG: Local stream available with tracks:");
      _localStream!.getTracks().forEach((track) {
        print("DEBUG: - ${track.kind} track: ${track.id}, enabled: ${track.enabled}, label: ${track.label}");
      });
      
      // Add tracks - AFTER the PC is fully set up and handlers are attached
      print("DEBUG: Beginning to add tracks to PeerConnection");
      
      // Add all tracks in one go
      try {
        for (var track in _localStream!.getTracks()) {
          print("DEBUG: Adding ${track.kind} track: ${track.id}, ${track.label}");
          await pc.addTrack(track, _localStream!);
          print("DEBUG: ${track.kind} track added successfully");
        }
      } catch (e) {
        print("ERROR: Failed to add tracks: $e");
        // Continue anyway to create the offer - some implementations allow empty offers
      }
    }
    
    // Create offer
    print("DEBUG: Creating offer for $remoteUuid");
    try {
      print("DEBUG: Calling createOffer...");
      RTCSessionDescription s = await pc.createOffer(_sdpConstraints);
      print("DEBUG: Offer SDP created successfully");
      
      // Set local description
      print("DEBUG: Setting local description...");
      await pc.setLocalDescription(s);
      print("DEBUG: Local description set successfully");
      
      // Apply bitrate using SDP manipulation
      String sdp = s.sdp!;
      if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        // Get target bitrate
        int targetBitrate = getTargetBitrate();
        final params = {'min': (targetBitrate * 0.1).round(), 'max': targetBitrate};
        sdp = CodecsHandler.setVideoBitrates(sdp, params);
        print("DEBUG: Modified SDP with bitrate constraints: ${targetBitrate}kbps");
      }
      
      // Create modified description with updated SDP
      RTCSessionDescription description = RTCSessionDescription(sdp, s.type);
      
      // Prepare to send the offer
      print("DEBUG: Preparing to send offer");
      var request = <String, dynamic>{};
      request["UUID"] = remoteUuid;
      request["description"] = {'sdp': description.sdp, 'type': description.type};
      request["session"] = sessionId;
      request["streamID"] = streamID + hashcode;
      
      if (UUID.isNotEmpty) {
        request["from"] = UUID;
      }
      
      if (usepassword) {
        print("DEBUG: Encrypting offer");
        List<String> encrypted = await encryptMessage(jsonEncode(request["description"]));
        request["description"] = encrypted[0];
        request["vector"] = encrypted[1];
      }
      
      print("DEBUG: Sending offer to $remoteUuid");
      _safeSend(jsonEncode(request));
      print("DEBUG: Offer sent successfully");
      
    } catch (e) {
      print("ERROR: Failed to create/send offer: $e");
      _handleBye(remoteUuid);
    }
  } catch (e) {
    print("FATAL ERROR: _createPeerConnectionAndOffer failed: $e");
    _handleBye(remoteUuid);
  }
}
  // Helper to handle remote ICE candidates
  Future<void> _handleRemoteCandidate(
      String remoteUuid, Map<String, dynamic> mapData) async {
    var pc = _sessions[remoteUuid];
    if (pc == null ||
        pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      // print("Received candidate for unknown or closed session: $remoteUuid. Ignoring."); // Can be noisy
      return;
    }

    dynamic candidatesData = mapData.containsKey('candidate')
        ? mapData['candidate']
        : mapData['candidates'];

    // Decrypt if necessary
    if (usepassword && mapData.containsKey('vector')) {
      try {
        String decryptedJson =
            await decryptMessage(candidatesData as String, mapData['vector']);
        candidatesData =
            jsonDecode(decryptedJson); // Decode JSON after decryption
        // print("Decrypted remote candidate(s) from $remoteUuid."); // Can be noisy
      } catch (e) {
        print("Error decrypting candidate(s) from $remoteUuid: $e. Aborting.");
        return;
      }
    }

    List<Map<dynamic, dynamic>> candidateList = [];
    if (candidatesData is Map) {
      candidateList
          .add(Map<dynamic, dynamic>.from(candidatesData)); // Single candidate
    } else if (candidatesData is List) {
      candidateList = candidatesData
          .map((c) => Map<dynamic, dynamic>.from(c))
          .toList(); // List of candidates
    } else {
      print("Invalid candidate format received from $remoteUuid. Ignoring.");
      return;
    }

    // Process each candidate
    for (var candidateMap in candidateList) {
      if (candidateMap['candidate'] == null || candidateMap['sdpMid'] == null) {
        print(
            "Invalid candidate structure in list from $remoteUuid. Skipping.");
        continue;
      }
      try {
        // sdpMLineIndex is often nullable or not used in newer WebRTC versions with unified-plan
        RTCIceCandidate candidate = RTCIceCandidate(
            candidateMap['candidate'],
            candidateMap['sdpMid'],
            candidateMap[
                'sdpMLineIndex'] // Pass null if not present, library handles it
            );

        // Add candidate, schedule on microtask queue to avoid blocking
        Future.microtask(() async {
          try {
            if (_sessions.containsKey(remoteUuid) &&
                _sessions[remoteUuid]!.signalingState !=
                    RTCSignalingState.RTCSignalingStateClosed) {
              // print("Adding candidate for $remoteUuid: ${candidate.candidate}"); // Noisy
              await pc.addCandidate(candidate);
            }
          } catch (e) {
            // Ignore errors if PC is closed or candidate is invalid/duplicate
            if (!e.toString().contains("closed") &&
                !e.toString().contains("invalid")) {
              print("ERROR adding candidate for $remoteUuid: $e");
            }
          }
        });
      } catch (e) {
        print("Error creating RTCIceCandidate object for $remoteUuid: $e");
      }
    }
  }

  // Helper to handle 'bye' message
  void _handleBye(String remoteUuid) {
    print("Handling 'bye' for session: $remoteUuid");
    var pc = _sessions.remove(remoteUuid);
    _sessionID.remove(remoteUuid);

    if (pc != null) {
      try {
        pc.close(); // Close the peer connection
        print("Closed PeerConnection for $remoteUuid.");
      } catch (e) {
        print("Error closing PeerConnection for $remoteUuid during bye: $e");
      }
    }

    // If this was the last peer, potentially update call state
    if (_sessions.isEmpty) {
      print("All peers disconnected.");
      onCallStateChange(CallState.CallStateBye);
    }
  }

  // Enhanced error recovery with exponential backoff
  Future<void> _handleConnectionError(String remoteUuid, String error) async {
    print("Connection error for $remoteUuid: $error");
    
    // Clean up the failed connection
    _cleanupPeerConnection(remoteUuid);
    
    // Check if we should attempt recovery
    if (active && reconnectionAttempt < maxReconnectionAttempts) {
      int delayMs = (initialReconnectDelayMs * pow(2, reconnectionAttempt)).toInt();
      delayMs = delayMs.clamp(initialReconnectDelayMs, maxReconnectDelayMs);
      
      reconnectionAttempt++;
      print('Attempting peer connection recovery #$reconnectionAttempt in ${delayMs / 1000} seconds for $remoteUuid...');
      
      Future.delayed(Duration(milliseconds: delayMs), () async {
        if (active && !_sessions.containsKey(remoteUuid)) {
          try {
            await _createPeerConnectionAndOffer(remoteUuid);
          } catch (e) {
            print("Error during peer connection recovery for $remoteUuid: $e");
            if (reconnectionAttempt >= maxReconnectionAttempts) {
              print("Max recovery attempts reached for $remoteUuid. Giving up.");
            }
          }
        }
      });
    } else {
      print("Max recovery attempts reached or signaling inactive for $remoteUuid");
    }
  }

  // Network quality monitoring
  void _startNetworkQualityMonitoring(String remoteUuid) {
    _networkQualityTimer?.cancel();
    _networkQualityTimer = Timer.periodic(Duration(milliseconds: networkQualityIntervalMs), (timer) async {
      if (!active || !_sessions.containsKey(remoteUuid)) {
        timer.cancel();
        return;
      }
      
      try {
        final pc = _sessions[remoteUuid];
        if (pc != null) {
          final stats = await pc.getStats();
          _analyzeNetworkStats(remoteUuid, stats);
        }
      } catch (e) {
        print("Error getting network stats for $remoteUuid: $e");
      }
    });
  }

  void _analyzeNetworkStats(String remoteUuid, List<StatsReport> stats) {
    try {
      // Analyze key metrics
      for (var report in stats) {
        if (report.type == 'outbound-rtp' && report.values['mediaType'] == 'video') {
          final bytesSent = report.values['bytesSent'];
          final packetsSent = report.values['packetsSent'];
          final packetsLost = report.values['packetsLost'] ?? 0;
          
          if (bytesSent != null && packetsSent != null) {
            _networkStats[remoteUuid] = {
              'bytesSent': bytesSent,
              'packetsSent': packetsSent,
              'packetsLost': packetsLost,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            
            // Calculate packet loss rate
            if (packetsSent > 0) {
              final lossRate = (packetsLost / (packetsSent + packetsLost)) * 100;
              if (lossRate > 5.0) { // More than 5% packet loss
                print("Warning: High packet loss rate for $remoteUuid: ${lossRate.toStringAsFixed(2)}%");
              }
            }
          }
          break;
        }
      }
    } catch (e) {
      print("Error analyzing network stats: $e");
    }
  }

  // Helper to send ICE candidate
  Future<void> _sendIceCandidate(String remoteUuid, String sessionId, RTCIceCandidate candidate) async {
		var request = <String, dynamic>{}; // Use Map literal
		request["UUID"] = remoteUuid; // Target UUID
		request["candidate"] = candidate.toMap(); // Use candidate's toMap method
		request["type"] = "local"; // Indicate it's a local candidate
		request["session"] = sessionId;
		request["streamID"] = streamID + hashcode;

		if (UUID.isNotEmpty) {
		  request["from"] = UUID; // Our UUID if using custom WSS
		}

		// Encrypt if needed
		if (usepassword) {
		  try {
			String candidateJson = jsonEncode(request["candidate"]);
			List<String> encrypted = await encryptMessage(candidateJson);
			request["candidate"] = encrypted[0];
			request["vector"] = encrypted[1];
		  } catch (e) {
			print("Error encrypting candidate: $e");
			return; // Don't send if encryption fails
		  }
		}

		// print("Sending ICE candidate to $remoteUuid"); // Noisy
		_safeSend(jsonEncode(request));
	  }
  

Future<void> connect() async {
    print("Starting connect() method");
    active = true;
    
    // If there's no local stream, create it
    if (_localStream == null) {
      try {
        print("No local stream exists, creating new stream");
        _localStream = await createStream();
        
        if (_localStream == null) {
          print("Failed to create local stream");
          throw Exception("Failed to create local stream");
        }
        
        print("Local stream created successfully with ID: ${_localStream!.id}");
        print("Tracks in local stream:");
        _localStream!.getTracks().forEach((track) {
          print("- ${track.kind} track: ${track.id}, enabled: ${track.enabled}, label: ${track.label}");
        });
        
        // Notify the app about the new stream
        onLocalStream?.call(_localStream!);
        onCallStateChange?.call(CallState.CallStateNew);
      } catch (e) {
        print("Error creating stream: $e");
        active = false;
        onSignalingStateChange(SignalingState.ConnectionError);
        return;
      }
    } else {
      print("Using existing local stream: ${_localStream!.id}");
    }
    
    // Start connection attempts
    reconnectionAttempt = 0;
    await attemptConnection();
  }
Future<void> attemptConnection() async {
    if (!active) {
      print("Connect attempt aborted (active is false).");
      return;
    }

    // Cancel any existing connection timer
    _connectionTimer?.cancel();
    
    // Start connection timeout
    _connectionTimer = Timer(Duration(milliseconds: connectionTimeoutMs), () {
      if (!_isSocketConnected && active) {
        print("Connection timeout after ${connectionTimeoutMs / 1000} seconds");
        try {
          _socket.close();
        } catch (e) {
          print("Error closing socket during timeout: $e");
        }
        _socket.onClose(1006, "Connection timeout");
      }
    });

    try {
      _socket = SimpleWebSocket();

      _socket.onOpen = () {
        print('WebSocket connection established to $WSSADDRESS');
        _isSocketConnected = true;
        reconnectionAttempt = 0;
        _connectionTimer?.cancel(); // Cancel timeout on successful connection
        onSignalingStateChange(SignalingState.ConnectionOpen);

        // Send initial seed/join messages
        try {
          var seedRequest = <String, dynamic>{
            "request": "seed",
            "streamID": streamID + hashcode,
          };
          if (UUID.isNotEmpty) seedRequest["from"] = UUID;
          _safeSend(_encoder.convert(seedRequest));
          print("Sent 'seed' request.");

          if (roomID.isNotEmpty) {
            var joinRequest = <String, dynamic>{
              "request": "joinroom",
              "roomid": roomhashcode.isNotEmpty ? roomhashcode : roomID,
            };
            if (UUID.isNotEmpty) joinRequest["from"] = UUID;
            _safeSend(_encoder.convert(joinRequest));
            print("Sent 'joinroom' request for room: ${joinRequest["roomid"]}");
          }
        } catch (e) {
          print('Error sending initial seed/join requests: $e');
        }
      };

      _socket.onMessage = (message) {
        try {
          onMessage(message);
        } catch (e) {
          print('Error processing WebSocket message: $e');
        }
      };

      _socket.onClose = (int code, String reason) {
        print('WebSocket connection closed. Code: $code, Reason: $reason');
        _isSocketConnected = false;
        if (!active) {
          print("Ignoring onClose event as signaling is inactive.");
          return;
        }
        onSignalingStateChange(SignalingState.ConnectionClosed);

        if (reconnectionAttempt < maxReconnectionAttempts) {
          int delayMs = (initialReconnectDelayMs * pow(2, reconnectionAttempt)).toInt();
          delayMs = delayMs.clamp(initialReconnectDelayMs, maxReconnectDelayMs);

          reconnectionAttempt++;
          print('Attempting reconnection #$reconnectionAttempt in ${delayMs / 1000} seconds...');

          Future.delayed(Duration(milliseconds: delayMs), () {
            if (active) {
              attemptConnection();
            } else {
              print("Reconnection attempt aborted (active is false).");
            }
          });
        } else {
          print('Max reconnection attempts reached ($maxReconnectionAttempts). Giving up.');
          active = false;
          onSignalingStateChange(SignalingState.ConnectionError);
          _cleanSessions();
        }
      };

      // Start connection
      print("Connecting to WebSocket URL: $WSSADDRESS");
      await _socket.connect(streamID + hashcode, WSSADDRESS, UUID);
    } catch (e) {
      print('WebSocket connection attempt failed: $e');
      _socket.onClose(1006, "Connection failed");
    }
  }

void _safeSend(String data) {
  if (_isSocketConnected) {
    try {
      _socket.send(data);
    } catch (e) {
      print("Error sending WebSocket message: $e");
      // Try to reconnect if sending fails
      if (active && _isSocketConnected) {
        _isSocketConnected = false;
        print("WebSocket send failed. Attempting to reconnect...");
        _socket.onClose(1006, "Send failed");
      }
    }
  } else {
    print("Cannot send message, WebSocket is not open.");
  }
}


  // Optional: Connection Timeout Handling (More complex, consider carefully)
  // Timer? _connectionTimer;
  // void handleConnectionTimeout(String sessionId, int timeoutMs) {
  //    _connectionTimer?.cancel();
  //    _connectionTimer = Timer(Duration(milliseconds: timeoutMs), () {
  //        if (_sessions.isEmpty && active) { // Check if still trying and no sessions established
  //             print("Initial connection timeout (${timeoutMs}ms). Closing connection attempt.");
  //             active = false;
  //             _socket?.close(1001, "Connection Timeout");
  //             onSignalingStateChange(SignalingState.ConnectionError);
  //             _cleanSessions();
  //        }
  //    });
  // }
  // --- End Connection Logic ---

Future<MediaStream> createStream() async {
  print("Starting createStream() method");
  
  // Create a dummy PC first for stability
  RTCPeerConnection? dummyPC;
  try {
    dummyPC = await createPeerConnection({
      'iceServers': [{'url': 'stun:stun.l.google.com:19302'}],
    }, {});
  } catch (e) {
    print("Failed to create dummy PeerConnection: $e");
  }
  
  try {
    // Set up resolution based on quality setting
    String width = quality ? "1920" : "1280";
    String height = quality ? "1080" : "720";
    String frameRate = quality ? "30" : "30";
    
    late MediaStream stream;
    
    if (deviceID == "screen") {
      print("Requesting screen sharing...");
      
      // For iOS, we need to use the proper broadcast extension approach
      if (Platform.isIOS) {
        print("Setting up iOS screen capture with broadcast extension");
        
        // Request permissions first
        await Permission.microphone.request();
		
		
        
        // IMPORTANT: When using a broadcast extension, use getDisplayMedia with 
        // a different constraint structure that explicitly mentions the extension
        Map<String, dynamic> screenConstraints = {
		  'video': {
			'deviceId': 'broadcast',
			'mandatory': {
			  'width': width,
			  'height': height,
			  'maxWidth': width,
			  'maxHeight': height,  // Fixed: was using width instead of height
			  'frameRate': frameRate
			},
		  },
		};
        
        stream = await navigator.mediaDevices.getDisplayMedia(screenConstraints);
        
        // Configure iOS audio session for screen sharing
        await initializeIOSAudioSession(forScreenShare: true);
      } else {
        // Android/Web implementation
        stream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'mandatory': {
              'minWidth': width,
              'maxWidth': width,
              'minHeight': height,
              'maxHeight': height,
              'maxFrameRate': frameRate,
            }
          },
        });
      }
    } else if (deviceID == "microphone") {
      print("Requesting audio-only...");
      Map<String, dynamic> audioConstraints = audioDeviceId == "default"
          ? {'mandatory': {'echoCancellation': false}}
          : {
              'mandatory': {'echoCancellation': false},
              'optional': [{'sourceId': audioDeviceId}]
            };
      
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': false
      });
    } else {
      print("Requesting camera and microphone...");
      
      // Determine facing mode
      String facingMode = "";
      if (deviceID == "front" || deviceID.contains("1") || deviceID == "user") {
        facingMode = "user";
      } else if (deviceID == "rear" || deviceID == "environment" || deviceID.contains("0")) {
        facingMode = "environment";
      }
      
      // Set up video constraints
      Map<String, dynamic> videoConstraints = {
        'mandatory': {
          'minWidth': width,
          'maxWidth': width,
          'minHeight': height,
          'maxHeight': height,
          'minFrameRate': frameRate,
          'maxFrameRate': frameRate,
        },
      };
      
      if (facingMode.isNotEmpty) {
        videoConstraints['facingMode'] = facingMode;
      } else {
        videoConstraints['deviceId'] = deviceID;
      }
      
      // Set up audio constraints
      Map<String, dynamic> audioConstraints = audioDeviceId == "default"
          ? {'mandatory': {'echoCancellation': false}}
          : {
              'mandatory': {'echoCancellation': false},
              'optional': [{'sourceId': audioDeviceId}]
            };
      
      // Get combined stream
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': videoConstraints
      });
    }
    
    // Print stream details
    print("Stream created with ID: ${stream.id}");
    print("Tracks in stream:");
    stream.getTracks().forEach((track) {
      print("- ${track.kind} track: ${track.id}, enabled: ${track.enabled}, label: ${track.label}");
    });
    
    // Clean up dummy PC
    if (dummyPC != null) {
      await dummyPC.close();
    }
    
    return stream;
  } catch (e) {
    print("createStream() failed: $e");
    
    // Clean up dummy PC on error
    if (dummyPC != null) {
      try {
        await dummyPC.close();
      } catch (_) {}
    }
    
    throw e;
  }
}

Future<void> _createOffer(String remoteUuid, String sessionId, RTCPeerConnection pc) async {
  print("Creating Offer for $remoteUuid...");
  try {
    // Check PC state first
    if (pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateClosed || 
        pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      print("Cannot create offer: PeerConnection is closed.");
      _handleBye(remoteUuid);
      return;
    }
    
    // Create offer with constraints
    RTCSessionDescription? offer;
    try {
      offer = await pc.createOffer(_sdpConstraints);
    } catch (e) {
      print("Error creating offer: $e");
      _handleBye(remoteUuid);
      return;
    }
    
    if (offer == null || offer.sdp == null || offer.sdp!.isEmpty) {
      print("Created offer is null or has empty SDP");
      _handleBye(remoteUuid);
      return;
    }
    
    // Apply bitrate modification
    int targetBitrate = getTargetBitrate();
    int minBitrate = targetBitrate ~/ 5; // Set minimum to 20% of target
    
    final params = {'min': minBitrate, 'max': targetBitrate};
    print("Setting video bitrates: min=${params['min']}kbps, max=${params['max']}kbps");
    
    String sdp = offer.sdp!;
    sdp = CodecsHandler.setVideoBitrates(sdp, params);
    
    // Create modified offer
    RTCSessionDescription modifiedOffer = RTCSessionDescription(sdp, offer.type);
    
    // Check PC state again before setting local description
    if (pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateClosed || 
        pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      print("Cannot set local description: PeerConnection became closed.");
      _handleBye(remoteUuid);
      return;
    }
    
    // Set local description
    print("Setting local description for $remoteUuid...");
    await pc.setLocalDescription(modifiedOffer);
    print("Local description set for $remoteUuid.");
    
    // Get current description after setting
    RTCSessionDescription? currentDescription = await pc.getLocalDescription();
    if (currentDescription == null || currentDescription.sdp == null) {
      throw Exception("Failed to set local description - still null after setLocalDescription");
    }
    
    // Prepare offer
    var request = <String, dynamic>{};
    request["UUID"] = remoteUuid;
    request["description"] = currentDescription.toMap();
    request["session"] = sessionId;
    request["streamID"] = streamID + hashcode;
    if (UUID.isNotEmpty) request["from"] = UUID;
    
    // Encrypt if needed
    if (usepassword) {
      try {
        List<String> encrypted = await encryptMessage(jsonEncode(request["description"]));
        request["description"] = encrypted[0];
        request["vector"] = encrypted[1];
        print("Offer description encrypted for $remoteUuid.");
      } catch (e) {
        print("Error encrypting offer for $remoteUuid: $e");
        return;
      }
    }
    
    print("Sending offer to $remoteUuid.");
    _safeSend(jsonEncode(request));
    
  } catch (e) {
    print("ERROR creating/sending offer for $remoteUuid: $e");
    _handleBye(remoteUuid);
  }
}
	
// Helper to detect device performance capability
Future<bool> _isHighPerformanceDevice() async {
  // Simple heuristic: check if device has enough memory
  // More sophisticated detection could check CPU cores, GPU, etc.
  try {
	if (Platform.isAndroid) {
	  const MethodChannel channel = MethodChannel('vdoninja/device_info');
	  final Map<String, dynamic> deviceData = await channel.invokeMapMethod('getDeviceInfo') ?? {};
	  // RAM in MB, considering 4GB+ as high-end
	  final int ramMB = deviceData['ramMB'] ?? 0;
	  return ramMB >= 4000;
	} else if (Platform.isIOS) {
	  // iOS devices are generally high-performance
	  // Could add more detailed detection if needed
	  return true;
	}
  } catch (e) {
	print("Error detecting device performance: $e");
  }
  // Default to false for safety (less demanding settings)
  return false;
}

  Future<void> _createAnswer(
      String remoteUuid, String sessionId, RTCPeerConnection pc) async {
		print("Creating Answer for $remoteUuid...");
		try {
		  RTCSessionDescription s =
			  await pc.createAnswer(_sdpConstraints); // Use defined constraints
		  print("Answer created. Setting local description for $remoteUuid.");
		  await pc.setLocalDescription(s);
		  print("Local description set for $remoteUuid.");
		  
		  // Apply bitrate using RTCRtpSender if we have video tracks
		  if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
		    // Get target bitrate (which now includes parsed SDP bitrate)
		    int targetBitrate = getTargetBitrate();
		    await setVideoBitrate(pc, targetBitrate);
		    print("Set video bitrate to ${targetBitrate}kbps for answer");
		  }

		  var request = <String, dynamic>{};
		  request["UUID"] = remoteUuid; // Target
		  request["description"] = s.toMap(); // Use toMap()
		  request["session"] = sessionId;
		  request["streamID"] = streamID + hashcode;
		  if (UUID.isNotEmpty) request["from"] = UUID; // Sender

		  // Encrypt if needed
		  if (usepassword) {
			try {
			  List<String> encrypted =
				  await encryptMessage(jsonEncode(request["description"]));
			  request["description"] = encrypted[0];
			  request["vector"] = encrypted[1];
			  print("Answer description encrypted for $remoteUuid.");
			} catch (e) {
			  print("Error encrypting answer for $remoteUuid: $e");
			  return;
			}
		  }

		  print("Sending answer to $remoteUuid.");
		  _safeSend(jsonEncode(request));
		} catch (e) {
		  print("ERROR creating/sending answer for $remoteUuid: $e");
		  // Handle error, maybe close connection?
		  _handleBye(remoteUuid);
		}
  }
  // --- End PeerConnection Offer/Answer Logic ---

  // --- Data Channel Methods (Keep stubs if not used, or implement fully) ---
  Future<void> _createDataChannel(RTCPeerConnection pc, String label) async {
    print("Attempting to create data channel '$label'...");
    try {
      RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
        ..ordered = true; // Example: Set options if needed
      // ..maxRetransmits = 30;
      RTCDataChannel channel =
          await pc.createDataChannel(label, dataChannelDict);
      print("Data channel '$label' created with ID: ${channel.id}");
      _addDataChannel(channel); // Setup handlers
      onDataChannel?.call(channel); // Notify app
    } catch (e) {
      print("Error creating data channel '$label': $e");
    }
  }

	void _addDataChannel(RTCDataChannel channel) {
	  print("Adding handlers for data channel '${channel.label}' (ID: ${channel.id})");
	  
	  try {
		channel.onDataChannelState = (state) {
		  print("Data channel '${channel.label}' state changed: $state");
		};
		
		channel.onMessage = (RTCDataChannelMessage data) {
		  print("Message received on data channel '${channel.label}': ${data.isBinary ? '<Binary Data>' : data.text}");
		  onDataChannelMessage?.call(channel, data);
		};
	  } catch (e) {
		print("Error setting up data channel handlers: $e");
	  }
	}

  // --- Cleanup Logic ---
  Future<void> _cleanSessions() async {
    print("Cleaning up sessions and resources...");
    active = false; // Mark as inactive

    // Cancel connection timeout timer
    _connectionTimer?.cancel();
    _connectionTimer = null;
    
    // Cancel network quality monitoring timer
    _networkQualityTimer?.cancel();
    _networkQualityTimer = null;
    
    // Clear rate limiting data
    _lastConnectionAttempts.clear();
    _networkStats.clear();

    // Dispose iOS silent audio player first
    if (Platform.isIOS) {
      _iosSilentAudio.dispose();
    }

    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (e) {
      print("Error resetting orientation preferences: $e");
    }

    // Stop and dispose local stream
    if (_localStream != null) {
      print("Stopping local stream tracks...");
      final tracks = _localStream!.getTracks();
      for (var track in tracks) {
        try {
          print("Stopping track: ${track.id} (${track.kind})");
          await track.stop();
        } catch (e) {
          print('Error stopping local track ${track.id}: $e');
        }
      }
      print("Disposing local stream...");
      try {
        await _localStream!.dispose();
      } catch (e) {
        print("Error disposing local stream: $e");
      }
      _localStream = null;
    }

    // Close all peer connections
    print("Closing peer connections...");
    List<String> sessionKeys =
        _sessions.keys.toList(); // Copy keys before iterating
    for (var uuid in sessionKeys) {
      print("Closing session for UUID: $uuid");
      var pc = _sessions.remove(uuid);
      _sessionID.remove(uuid); // Remove session ID mapping
      if (pc != null) {
        // Send 'bye' message before closing (optional, best effort)
        try {
          var request = <String, dynamic>{};
          request["UUID"] = uuid;
          request["bye"] = true;
          if (UUID.isNotEmpty) request["from"] = UUID;
          _safeSend(jsonEncode(request)); // Send bye
          print("Sent 'bye' to $uuid.");
        } catch (e) {
          print("Error sending 'bye' to $uuid: $e");
        }

        // Close the connection
        try {
          await pc.close();
          print("PeerConnection closed for $uuid.");
        } catch (e) {
          print('Error closing PeerConnection for $uuid: $e');
        }
      }
    }
    _sessions.clear(); // Ensure map is empty
    _sessionID.clear();

    // Close the WebSocket connection
    if (_isSocketConnected) {
      // <--- CHECK IF IT WAS CONNECTED BEFORE TRYING TO CLOSE
      print("Closing WebSocket connection...");
      try {
        // await _socket.close(1000, "Client closed"); // See point 4 below
        await _socket.close(); // Use close() without arguments
        _isSocketConnected = false; // Ensure state is updated after closing
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
    } else {
      print("WebSocket already closed or never connected during cleanup.");
    }

    print("Cleanup complete.");
  }
  // --- End Cleanup Logic ---
  
  // --- Public Bitrate Control Methods ---
  Future<void> setCustomBitrate(int bitrateKbps) async {
    customBitrate = bitrateKbps;
    print("Custom bitrate set to ${bitrateKbps}kbps");
    
    // Apply to all active connections
    for (var entry in _sessions.entries) {
      if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        int targetBitrate = getTargetBitrate();
        await setVideoBitrate(entry.value, targetBitrate);
        print("Updated bitrate to ${targetBitrate}kbps for ${entry.key}");
      }
    }
  }
  
  void resetBitrate() {
    customBitrate = 0;
    sdpBitrate = 0;
    print("Bitrate settings reset to defaults");
  }
  
  Map<String, dynamic> getBitrateInfo() {
    return {
      'currentBitrate': getTargetBitrate(),
      'customBitrate': customBitrate,
      'sdpBitrate': sdpBitrate,
      'defaultBitrate': quality ? 10000 : 6000,
      'quality': quality,
    };
  }
  // --- End Public Bitrate Control Methods ---
} // End of Signaling Class
