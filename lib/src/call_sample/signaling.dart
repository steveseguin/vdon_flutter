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
import 'package:flutter_background/flutter_background.dart';

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
  static String preferCodec(String sdp, String? codec, {bool useRed = false, bool useUlpfec = false}) {
    if (codec != null) {
      codec = codec.toLowerCase();
    }
    
    final info = _splitLines(sdp);
    if (info.videoCodecNumbers == null || info.videoCodecNumbers!.isEmpty) {
      return sdp;
    }
    
    String preferCodecNumber = '';
    List<String> preferErrorCorrectionNumbers = [];
    
    if (codec == 'vp8') {
      preferCodecNumber = info.vp8LineNumber ?? '';
    } else if (codec == 'vp9') {
      preferCodecNumber = info.vp9LineNumber ?? '';
    } else if (codec == 'h264') {
      preferCodecNumber = info.h264LineNumber ?? '';
    } else if (codec == 'h265') {
      preferCodecNumber = info.h265LineNumber ?? '';
    } else if (codec == 'av1') {
      preferCodecNumber = info.av1LineNumber ?? '';
    } else if (codec == 'red') {
      preferCodecNumber = info.redLineNumber ?? '';
    } else if (codec == 'fec') {
      preferCodecNumber = info.ulpfecLineNumber ?? '';
    }
    
    if (useRed && info.redLineNumber != null) {
      preferErrorCorrectionNumbers.add(info.redLineNumber!);
    }
    if (useUlpfec && info.ulpfecLineNumber != null) {
      preferErrorCorrectionNumbers.add(info.ulpfecLineNumber!);
    }
    
    if (preferCodecNumber.isEmpty) {
      return sdp;
    }
    
    List<String> newOrder = [preferCodecNumber, ...preferErrorCorrectionNumbers];
    for (String codecNumber in info.videoCodecNumbers!) {
      if (!newOrder.contains(codecNumber)) {
        newOrder.add(codecNumber);
      }
    }
    
    final parts = info.videoCodecNumbersOriginal!.split('SAVPF');
    final newLine = '${parts[0]}SAVPF ${newOrder.join(' ')}';
    sdp = sdp.replaceAll(info.videoCodecNumbersOriginal!, newLine);
    
    return sdp;
  }
  
  static _CodecInfo _splitLines(String sdp) {
    final info = _CodecInfo();
    final lines = sdp.split('\n');
    
    for (String line in lines) {
      if (line.indexOf('m=video') == 0) {
        info.videoCodecNumbers = [];
        final savpfParts = line.split('SAVPF');
        if (savpfParts.length > 1) {
          final codecNumbers = savpfParts[1].split(' ');
          for (String codecNumber in codecNumbers) {
            codecNumber = codecNumber.trim();
            if (codecNumber.isNotEmpty) {
              info.videoCodecNumbers!.add(codecNumber);
            }
          }
          info.videoCodecNumbersOriginal = line;
        }
      }
      
      final upperLine = line.toUpperCase();
      if (upperLine.contains('VP8/90000') && info.vp8LineNumber == null) {
        info.vp8LineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (upperLine.contains('VP9/90000') && info.vp9LineNumber == null) {
        info.vp9LineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (upperLine.contains('H264/90000') && info.h264LineNumber == null) {
        info.h264LineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (upperLine.contains('H265/90000') && info.h265LineNumber == null) {
        info.h265LineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if ((upperLine.contains('AV1X/90000') || upperLine.contains('AV1/90000')) && info.av1LineNumber == null) {
        info.av1LineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (upperLine.contains('RED/90000') && info.redLineNumber == null) {
        info.redLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (upperLine.contains('ULPFEC/90000') && info.ulpfecLineNumber == null) {
        info.ulpfecLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
    }
    
    return info;
  }
  
  static String preferAudioCodec(String sdp, String? codec, {bool useRed = false, bool useUlpfec = false}) {
    codec = codec?.toLowerCase();
    final info = _splitAudioLines(sdp);
    
    if (info.audioCodecNumbers == null || info.audioCodecNumbers!.isEmpty) {
      return sdp;
    }
    
    String preferCodecNumber = '';
    List<String> errorCorrectionNumbers = [];
    
    // Set preferred codec number
    if (codec != null && info.codecLineNumbers[codec] != null) {
      preferCodecNumber = info.codecLineNumbers[codec]!;
    }
    
    // Handle RED/ULPFEC error correction
    if (useRed && info.redLineNumber != null) {
      if (info.redPcmLineNumber != null) {
        errorCorrectionNumbers.add(info.redPcmLineNumber!);
      } else if (info.redLineNumber != null) {
        errorCorrectionNumbers.add(info.redLineNumber!);
      }
    }
    if (useUlpfec && info.ulpfecLineNumber != null) {
      errorCorrectionNumbers.add(info.ulpfecLineNumber!);
    }
    
    // Set codec order: error correction + preferred codec + others
    List<String> newOrder = [...errorCorrectionNumbers];
    if (preferCodecNumber.isNotEmpty) {
      newOrder.add(preferCodecNumber);
    }
    
    for (String codecNumber in info.audioCodecNumbers!) {
      if (!newOrder.contains(codecNumber)) {
        newOrder.add(codecNumber);
      }
    }
    
    // Replace SDP line with updated codec order
    final parts = info.audioCodecNumbersOriginal!.split('SAVPF');
    final newLine = '${parts[0]}SAVPF ${newOrder.join(' ')}';
    sdp = sdp.replaceAll(info.audioCodecNumbersOriginal!, newLine);
    
    return sdp;
  }
  
  static _AudioCodecInfo _splitAudioLines(String sdp) {
    final info = _AudioCodecInfo();
    final lines = sdp.split('\n');
    
    for (String line in lines) {
      if (line.indexOf('m=audio') == 0) {
        info.audioCodecNumbers = [];
        final savpfParts = line.split('SAVPF');
        if (savpfParts.length > 1) {
          final codecNumbers = savpfParts[1].split(' ');
          for (String codecNumber in codecNumbers) {
            codecNumber = codecNumber.trim();
            if (codecNumber.isNotEmpty) {
              info.audioCodecNumbers!.add(codecNumber);
            }
          }
          info.audioCodecNumbersOriginal = line;
        }
      }
      
      final lowerLine = line.toLowerCase();
      if (lowerLine.contains('opus/48000') && info.codecLineNumbers['opus'] == null) {
        info.codecLineNumbers['opus'] = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('isac/32000') && info.codecLineNumbers['isac'] == null) {
        info.codecLineNumbers['isac'] = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('g722/8000') && info.codecLineNumbers['g722'] == null) {
        info.codecLineNumbers['g722'] = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('pcmu/8000') && info.codecLineNumbers['pcmu'] == null) {
        info.codecLineNumbers['pcmu'] = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('pcma/8000') && info.codecLineNumbers['pcma'] == null) {
        info.codecLineNumbers['pcma'] = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('red/48000') && info.redLineNumber == null) {
        info.redLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('ulpfec/48000') && info.ulpfecLineNumber == null) {
        info.ulpfecLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('red/8000') && info.redPcmLineNumber == null) {
        info.redPcmLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
      if (lowerLine.contains('ulpfec/8000') && info.ulpfecLineNumber == null) {
        info.ulpfecLineNumber = line.replaceAll('a=rtpmap:', '').split(' ')[0];
      }
    }
    
    return info;
  }
  
  static String disableNACK(String sdp) {
    if (sdp.isEmpty) {
      throw 'Invalid arguments.';
    }
    
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) nack\r\n'), '');
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) nack pli\r\n'), r'a=rtcp-fb:$1 pli\r\n');
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) pli nack\r\n'), r'a=rtcp-fb:$1 pli\r\n');
    
    return sdp;
  }
  
  static String disableREMB(String sdp) {
    if (sdp.isEmpty) {
      throw 'Invalid arguments.';
    }
    
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) goog-remb\r\n'), '');
    
    return sdp;
  }
  
  static String disablePLI(String sdp) {
    if (sdp.isEmpty) {
      throw 'Invalid arguments.';
    }
    
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) pli\r\n'), '');
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) nack pli\r\n'), r'a=rtcp-fb:$1 nack\r\n');
    sdp = sdp.replaceAll(RegExp(r'a=rtcp-fb:(\d+) pli nack\r\n'), r'a=rtcp-fb:$1 nack\r\n');
    
    return sdp;
  }
  
  static int? _findLine(List<String> sdpLines, String prefix, [String? substr]) {
    return _findLineInRange(sdpLines, 0, -1, prefix, substr);
  }
  
  static int? _findLineInRange(List<String> sdpLines, int startLine, int endLine, String prefix, [String? substr]) {
    final realEndLine = endLine != -1 ? endLine : sdpLines.length;
    for (int i = startLine; i < realEndLine; i++) {
      if (sdpLines[i].indexOf(prefix) == 0) {
        if (substr == null || sdpLines[i].toLowerCase().contains(substr.toLowerCase())) {
          return i;
        }
      }
    }
    return null;
  }
  
  static String _getCodecPayloadType(String sdpLine) {
    final pattern = RegExp(r'a=rtpmap:(\d+) \w+\/\d+');
    final result = pattern.firstMatch(sdpLine);
    return (result != null && result.groupCount >= 1) ? result.group(1)! : '';
  }
  
  static int getVideoBitrates(String sdp) {
    const defaultBitrate = 0;
    
    final sdpLines = sdp.split('\r\n');
    final mLineIndex = _findLine(sdpLines, 'm=', 'video');
    if (mLineIndex == null) {
      return defaultBitrate;
    }
    
    final videoMLine = sdpLines[mLineIndex];
    final pattern = RegExp(r'm=video\s\d+\s[A-Z/]+\s');
    final match = pattern.firstMatch(videoMLine);
    if (match == null) {
      return defaultBitrate;
    }
    
    final remaining = videoMLine.substring(match.end);
    final sendPayloadType = remaining.split(' ')[0];
    
    final rtpmapIndex = _findLine(sdpLines, 'a=rtpmap', sendPayloadType);
    if (rtpmapIndex == null) {
      return defaultBitrate;
    }
    
    final fmtpLine = sdpLines[rtpmapIndex];
    final codec = fmtpLine.split('a=rtpmap:$sendPayloadType')[1].split('/')[0];
    
    final codecIndex = _findLine(sdpLines, 'a=rtpmap', '$codec/90000');
    String? codecPayload;
    if (codecIndex != null) {
      codecPayload = _getCodecPayloadType(sdpLines[codecIndex]);
    }
    
    if (codecPayload == null || codecPayload.isEmpty) {
      return defaultBitrate;
    }
    
    final rtxIndex = _findLine(sdpLines, 'a=rtpmap', 'rtx/90000');
    if (rtxIndex == null) {
      return defaultBitrate;
    }
    
    final rtxFmtpLineIndex = _findLine(sdpLines, 'a=fmtp:$codecPayload');
    if (rtxFmtpLineIndex != null) {
      try {
        String line = sdpLines[rtxFmtpLineIndex];
        if (line.contains('x-google-max-bitrate=')) {
          final maxBitrateStr = line.split('x-google-max-bitrate=')[1].split(';')[0];
          final maxBitrate = int.parse(maxBitrateStr);
          
          int minBitrate = 0;
          if (line.contains('x-google-min-bitrate=')) {
            final minBitrateStr = line.split('x-google-min-bitrate=')[1].split(';')[0];
            minBitrate = int.parse(minBitrateStr);
          }
          
          if (minBitrate > maxBitrate) {
            return minBitrate;
          }
          return maxBitrate < 1 ? 1 : maxBitrate;
        }
      } catch (e) {
        return defaultBitrate;
      }
    }
    
    return defaultBitrate;
  }
  
  static String setVideoBitrates(String sdp, Map<String, dynamic>? params, [String? codec]) {
    codec = codec?.toUpperCase() ?? 'VP8';
    print("setVideoBitrates called with params: $params, codec: $codec");
    
    // First check if bitrate is already set in the SDP
    final existingBitrate = parseBitrateFromSdp(sdp);
    if (existingBitrate != null && existingBitrate > 0) {
      print("setVideoBitrates: Bitrate already set in SDP: ${existingBitrate}kbps, not modifying");
      return sdp;
    }
    
    var sdpLines = sdp.split('\r\n');
    
    // Search for m line
    final mLineIndex = _findLine(sdpLines, 'm=', 'video');
    if (mLineIndex == null) {
      print("setVideoBitrates: No video m-line found in SDP");
      return sdp;
    }
    
    // Figure out the first codec payload type on the m=video SDP line
    final videoMLine = sdpLines[mLineIndex];
    final pattern = RegExp(r'm=video\s\d+\s[A-Z/]+\s');
    final match = pattern.firstMatch(videoMLine);
    
    if (match != null) {
      final remaining = videoMLine.substring(match.end);
      final sendPayloadType = remaining.split(' ')[0];
      final rtpmapIndex = _findLine(sdpLines, 'a=rtpmap', sendPayloadType);
      
      if (rtpmapIndex != null) {
        final fmtpLine = sdpLines[rtpmapIndex];
        final codecName = fmtpLine.split('a=rtpmap:$sendPayloadType')[1].split('/')[0];
        codec = codecName.isNotEmpty ? codecName : codec;
      }
    }
    
    params = params ?? {};
    
    final minBitrate = params['min']?.toString() ?? '30';
    final maxBitrate = params['max']?.toString() ?? '2500';
    
    final codecIndex = _findLine(sdpLines, 'a=rtpmap', '$codec/90000');
    String? codecPayload;
    if (codecIndex != null) {
      codecPayload = _getCodecPayloadType(sdpLines[codecIndex]);
    }
    
    if (codecPayload == null || codecPayload.isEmpty) {
      print("setVideoBitrates: No codec payload found");
      return sdp;
    }
    
    print("setVideoBitrates: Found codec payload: $codecPayload for codec: $codec");
    
    final rtxIndex = _findLine(sdpLines, 'a=rtpmap', 'rtx/90000');
    String? rtxPayload;
    if (rtxIndex != null) {
      rtxPayload = _getCodecPayloadType(sdpLines[rtxIndex]);
    }
    
    if (rtxIndex == null) {
      print("setVideoBitrates: No RTX found, adding bandwidth constraints after m=video line");
      // Insert multiple bandwidth constraints for better compatibility
      sdpLines.insert(mLineIndex + 1, 'b=AS:$maxBitrate');
      sdpLines.insert(mLineIndex + 2, 'b=CT:$maxBitrate');  // Conference Total
      sdpLines.insert(mLineIndex + 3, 'b=TIAS:${maxBitrate * 1000}');  // Transport Independent Application Specific (in bits)
      
      final modifiedSdp = sdpLines.join('\r\n');
      
      // Verify the modification
      final verifyBitrate = parseBitrateFromSdp(modifiedSdp);
      print("setVideoBitrates: Verification - bitrate is now ${verifyBitrate}kbps");
      
      return modifiedSdp;
    }
    
    final rtxFmtpLineIndex = _findLine(sdpLines, 'a=fmtp:$rtxPayload');
    if (rtxFmtpLineIndex != null) {
      var appendrtxNext = '\r\n';
      appendrtxNext += 'a=fmtp:$codecPayload x-google-min-bitrate=$minBitrate; x-google-max-bitrate=$maxBitrate';
      sdpLines[rtxFmtpLineIndex] = sdpLines[rtxFmtpLineIndex] + appendrtxNext;
      print("setVideoBitrates: Added x-google-min-bitrate=$minBitrate; x-google-max-bitrate=$maxBitrate");
      
      // Also add b=AS line for better compatibility
      sdpLines.insert(mLineIndex + 1, 'b=AS:$maxBitrate');
      print("setVideoBitrates: Also added b=AS:$maxBitrate for compatibility");
    } else {
      print("setVideoBitrates: No RTX fmtp line found, adding b=AS:$maxBitrate");
      // Fallback: add b=AS line if we can't add fmtp parameters
      sdpLines.insert(mLineIndex + 1, 'b=AS:$maxBitrate');
    }
    
    final modifiedSdp = sdpLines.join('\r\n');
    
    // Verify the modification
    final verifyBitrate = parseBitrateFromSdp(modifiedSdp);
    print("setVideoBitrates: Verification - bitrate is now ${verifyBitrate}kbps");
    
    return modifiedSdp;
  }
  
  static List<String> _processOpus(List<String> sdpLines, String opusPayload, int opusIndex, 
      String codecType, Map<String, dynamic> params, bool debug) {
    final opusFmtpLineIndex = _findLine(sdpLines, 'a=fmtp:$opusPayload');
    if (opusFmtpLineIndex == null) {
      return sdpLines;
    }
    
    var appendOpusNext = '';
    
    if (params.containsKey('minptime') && params['minptime'] != false) {
      appendOpusNext += ';minptime:${params['minptime']}';
    }
    
    if (params.containsKey('maxptime') && params['maxptime'] != false) {
      appendOpusNext += ';maxptime:${params['maxptime']}';
    }
    
    if (params.containsKey('ptime') && params['ptime'] != false) {
      appendOpusNext += ';ptime:${params['ptime']}';
    }
    
    if (params.containsKey('stereo')) {
      // Remove existing stereo settings
      sdpLines[opusFmtpLineIndex] = sdpLines[opusFmtpLineIndex]
          .replaceAll(RegExp(r';stereo=[01]'), '')
          .replaceAll(RegExp(r';sprop-stereo=[01]'), '');
      
      if (params['stereo'] == 1) {
        appendOpusNext += ';stereo=1;sprop-stereo=1';
      } else if (params['stereo'] == 0) {
        appendOpusNext += ';stereo=0;sprop-stereo=0';
      } else if (params['stereo'] == 2 && codecType == 'OPUS') {
        sdpLines[opusIndex] = sdpLines[opusIndex].replaceAll('opus/48000/2', 'multiopus/48000/6');
        appendOpusNext += ';channel_mapping=0,4,1,2,3,5;num_streams=4;coupled_streams=2';
      } else if (params['stereo'] == 3 && codecType == 'OPUS') {
        sdpLines[opusIndex] = sdpLines[opusIndex].replaceAll('opus/48000/2', 'multiopus/48000/8');
        appendOpusNext += ';channel_mapping=0,6,1,2,3,4,5,7;num_streams=5;coupled_streams=4';
      }
    }
    
    if (params.containsKey('maxaveragebitrate')) {
      if (!sdpLines[opusFmtpLineIndex].contains('maxaveragebitrate=')) {
        appendOpusNext += ';maxaveragebitrate=${params['maxaveragebitrate']}';
      }
    }
    
    if (params.containsKey('maxplaybackrate')) {
      if (!sdpLines[opusFmtpLineIndex].contains('maxplaybackrate=')) {
        appendOpusNext += ';maxplaybackrate=${params['maxplaybackrate']}';
      }
    }
    
    if (params.containsKey('cbr')) {
      if (!sdpLines[opusFmtpLineIndex].contains('cbr=')) {
        appendOpusNext += ';cbr=${params['cbr']}';
      }
    }
    
    if (params.containsKey('dtx') && params['dtx'] == true) {
      if (!sdpLines[opusFmtpLineIndex].contains('usedtx=')) {
        appendOpusNext += ';usedtx=1';
      }
    }
    
    if (params.containsKey('useinbandfec')) {
      if (!sdpLines[opusFmtpLineIndex].contains('useinbandfec=')) {
        appendOpusNext += ';useinbandfec=${params['useinbandfec']}';
      } else {
        final oldValue = params['useinbandfec'] == 1 ? 0 : 1;
        sdpLines[opusFmtpLineIndex] = sdpLines[opusFmtpLineIndex]
            .replaceAll('useinbandfec=$oldValue', 'useinbandfec=${params['useinbandfec']}');
      }
    }
    
    if (appendOpusNext.isNotEmpty) {
      sdpLines[opusFmtpLineIndex] = sdpLines[opusFmtpLineIndex] + appendOpusNext;
    }
    
    if (debug) {
      print('Adding to SDP ($codecType): $appendOpusNext --> Result: ${sdpLines[opusFmtpLineIndex]}');
    }
    
    return sdpLines;
  }
  
  static String setOpusAttributes(String sdp, Map<String, dynamic>? params, {bool debug = false}) {
    params = params ?? {};
    
    var sdpLines = sdp.split('\r\n');
    
    final opusIndex = _findLine(sdpLines, 'a=rtpmap', 'opus/48000');
    String? opusPayload;
    if (opusIndex != null) {
      opusPayload = _getCodecPayloadType(sdpLines[opusIndex]);
    }
    
    final redIndex = _findLine(sdpLines, 'a=rtpmap', 'red/48000');
    String? redPayload;
    if (redIndex != null) {
      redPayload = _getCodecPayloadType(sdpLines[redIndex]);
    }
    
    if ((opusPayload == null || opusPayload.isEmpty) && 
        (redPayload == null || redPayload.isEmpty)) {
      return sdp;
    }
    
    if (opusPayload != null && opusPayload.isNotEmpty) {
      if (debug) print('Processing OPUS codec');
      sdpLines = _processOpus(sdpLines, opusPayload, opusIndex!, 'OPUS', params, debug);
    }
    
    if (redPayload != null && redPayload.isNotEmpty) {
      if (debug) print('Processing RED codec');
      sdpLines = _processOpus(sdpLines, redPayload, redIndex!, 'RED', params, debug);
    }
    
    return sdpLines.join('\r\n');
  }
  
  static int getOpusBitrate(String sdp) {
    final sdpLines = sdp.split('\r\n');
    
    final opusIndex = _findLine(sdpLines, 'a=rtpmap', 'opus/48000');
    String? opusPayload;
    if (opusIndex != null) {
      opusPayload = _getCodecPayloadType(sdpLines[opusIndex]);
    }
    
    if (opusPayload == null || opusPayload.isEmpty) {
      return 0;
    }
    
    final opusFmtpLineIndex = _findLine(sdpLines, 'a=fmtp:$opusPayload');
    if (opusFmtpLineIndex == null) {
      return 0;
    }
    
    final line = sdpLines[opusFmtpLineIndex];
    if (line.contains('maxaveragebitrate=')) {
      try {
        var tmp = line.split('maxaveragebitrate=')[1];
        tmp = tmp.split('\r')[0];
        tmp = tmp.split('\n')[0];
        tmp = tmp.split(';')[0];
        return int.parse(tmp);
      } catch (e) {
        return 32768;
      }
    }
    
    return 32768;
  }
  
  static String modifyDescLyra(String modifiedSDP) {
    if (!modifiedSDP.contains('m=audio')) {
      return modifiedSDP;
    }
    
    modifiedSDP = modifiedSDP
        .replaceAll('SAVPF 111', 'SAVPF 109 111')
        .replaceAll('a=rtpmap:111', 'a=rtpmap:109 L16/16000/1\r\na=fmtp:109 ptime=20\r\na=rtpmap:111');
    
    modifiedSDP = modifiedSDP
        .replaceAll('a=rtpmap:106 CN/32000\r\n', '')
        .replaceAll('a=rtpmap:105 CN/16000\r\n', '')
        .replaceAll('a=rtpmap:13 CN/8000\r\n', '')
        .replaceAll(' 106 105 13', '');
    
    return modifiedSDP;
  }
  
  static String modifyDescPCM(String modifiedSDP, {int rate = 32000, bool stereo = false, int? ptimeOverride}) {
    if (!modifiedSDP.contains('m=audio')) {
      return modifiedSDP;
    }
    
    int ptime = 10;
    if (ptimeOverride != null) {
      ptime = ptimeOverride;
    }
    ptime = (ptime ~/ 10) * 10;
    if (ptime < 10) {
      ptime = 10;
    }
    
    if (!stereo && rate >= 48000) {
      rate = 48000;
      ptime = 10;
    } else if (!stereo && rate >= 44100) {
      rate = 44100;
      ptime = 10;
    } else if (rate >= 32000) {
      rate = 32000;
      if (stereo) {
        ptime = 10;
      } else if (ptime > 20) {
        ptime = 20;
      }
    } else if (rate >= 16000) {
      rate = 16000;
      if (stereo) {
        if (ptime > 20) {
          ptime = 20;
        }
      } else if (ptime > 40) {
        ptime = 40;
      }
    } else {
      rate = 8000;
      if (stereo) {
        if (ptime > 40) {
          ptime = 40;
        }
      }
    }
    
    final channels = stereo ? '2' : '1';
    modifiedSDP = modifiedSDP
        .replaceAll('SAVPF 111', 'SAVPF 109 111')
        .replaceAll('a=rtpmap:111', 'a=rtpmap:109 L16/$rate/$channels\r\na=fmtp:109 ptime=$ptime\r\na=rtpmap:111');
    
    modifiedSDP = modifiedSDP
        .replaceAll('a=rtpmap:106 CN/32000\r\n', '')
        .replaceAll('a=rtpmap:105 CN/16000\r\n', '')
        .replaceAll('a=rtpmap:13 CN/8000\r\n', '')
        .replaceAll(' 106 105 13', '');
    
    return modifiedSDP;
  }
  
  static String modifySdp(String sdp, {bool disableAudio = false, bool disableVideo = false}) {
    if (sdp.isEmpty) {
      throw 'Invalid arguments.';
    }
    
    final sdpLines = sdp.split('\r\n');
    final modifiedLines = <String>[];
    bool inAudioSection = false;
    bool inVideoSection = false;
    final bundleIds = <String>[];
    
    for (String line in sdpLines) {
      if (line.startsWith('m=audio')) {
        inAudioSection = true;
        inVideoSection = false;
        if (!disableAudio) {
          modifiedLines.add(line);
          bundleIds.add('0');
        }
      } else if (line.startsWith('m=video')) {
        inAudioSection = false;
        inVideoSection = true;
        if (!disableVideo) {
          modifiedLines.add(line);
          bundleIds.add('1');
        } else {
          modifiedLines.add(''); // Add a line break if video is disabled
        }
      } else if (inVideoSection && disableVideo) {
        continue; // Skip video lines if video is disabled
      } else if (line.startsWith('a=group:')) {
        // Skip existing group lines, we'll add updated ones later
      } else if (inAudioSection && disableAudio) {
        // Skip audio lines if audio is disabled
      } else {
        modifiedLines.add(line);
      }
    }
    
    final tLineIndex = modifiedLines.indexWhere((line) => line.startsWith('t='));
    if (bundleIds.isNotEmpty && tLineIndex != -1) {
      modifiedLines.insert(tLineIndex + 1, 'a=group:BUNDLE ${bundleIds.join(' ')}');
      modifiedLines.insert(tLineIndex + 2, 'a=group:LS ${bundleIds.join(' ')}');
    }
    
    // Ensure there's a line break at the end
    if (modifiedLines.isNotEmpty && modifiedLines.last.isNotEmpty) {
      modifiedLines.add('');
    }
    
    return modifiedLines.join('\r\n');
  }
  
  // Parse bitrate from incoming SDP (addition to match your original Dart code)
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
}

// Helper classes for codec information
class _CodecInfo {
  List<String>? videoCodecNumbers;
  String? videoCodecNumbersOriginal;
  String? vp8LineNumber;
  String? vp9LineNumber;
  String? h264LineNumber;
  String? h265LineNumber;
  String? av1LineNumber;
  String? redLineNumber;
  String? ulpfecLineNumber;
}

class _AudioCodecInfo {
  List<String>? audioCodecNumbers;
  String? audioCodecNumbersOriginal;
  Map<String, String> codecLineNumbers = {};
  String? redLineNumber;
  String? ulpfecLineNumber;
  String? redPcmLineNumber;
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
    } else {
      print("No custom bitrate specified, will use defaults (720p: 6000kbps, 1080p: 10000kbps)");
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
    
    // Get only the new audio track with advanced constraints
    final newAudioStream = await navigator.mediaDevices.getUserMedia({
      'audio': await _buildAdvancedAudioConstraints(audioDeviceId),
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
      print("Using SDP bitrate: ${sdpBitrate}kbps");
      return sdpBitrate;
    }
    
    if (customBitrate > 0) {
      print("Using custom bitrate: ${customBitrate}kbps");
      return customBitrate;
    }
    
    // Default bitrates: 6mbps for 720p, 10mbps for 1080p
    int defaultBitrate = quality ? 10000 : 6000;
    print("Using default bitrate: ${defaultBitrate}kbps (quality: $quality)");
    return defaultBitrate;
  }
  
  // --- End Video Bitrate Control ---
  
  // Trigger renegotiation to apply new bitrate settings
  Future<void> _triggerRenegotiation(String remoteUuid, RTCPeerConnection pc) async {
    try {
      print("Triggering renegotiation for $remoteUuid to apply bitrate changes");
      
      // Check if we can renegotiate
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        print("Cannot renegotiate: signaling state is not stable");
        return;
      }
      
      // Create a new offer with updated bitrate
      await _createOffer(remoteUuid, _sessionID[remoteUuid]!, pc);
    } catch (e) {
      print("Error triggering renegotiation: $e");
    }
  }

  // --- WebSocket and PeerConnection Management ---
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  late SimpleWebSocket _socket;
  bool _isSocketConnected = false;
  // var _port = 443; // Not used directly if WSSADDRESS includes port
  var _sessions = <String, RTCPeerConnection>{}; // Explicit type
  var _remoteSDPs = <String, String>{}; // Store remote SDPs by UUID
  var _sessionID = <String, String>{}; // Explicit type
  var _lowBitrateCount = <String, int>{}; // Track low bitrate occurrences per peer
  var _peerBitrates = <String, int>{}; // Store per-peer bitrate preferences

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
    
    // Store the original remote SDP for later reference
    _remoteSDPs[remoteUuid] = sdp;
    
    // Parse bitrate from incoming SDP
    final parsedBitrate = CodecsHandler.parseBitrateFromSdp(sdp);
    if (parsedBitrate != null && parsedBitrate > 0) {
      print("Parsed bitrate from incoming SDP: ${parsedBitrate}kbps");
      sdpBitrate = parsedBitrate;
    }
    
    // If this is an answer and it doesn't have bitrate, add our default bitrate
    if (type == 'answer' && _localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      if (parsedBitrate == null || parsedBitrate == 0) {
        print("Answer does not have bitrate, applying our default");
        int targetBitrate = customBitrate > 0 ? customBitrate : (quality ? 10000 : 6000);
        final params = {'min': (targetBitrate * 0.8).round(), 'max': targetBitrate};
        sdp = CodecsHandler.setVideoBitrates(sdp, params);
        print("Modified answer SDP with bitrate: min=${params['min']}kbps, max=${params['max']}kbps");
        
        // Verify the bitrate was added
        final verifyBitrate = CodecsHandler.parseBitrateFromSdp(sdp);
        print("Verification: answer SDP now has bitrate: ${verifyBitrate}kbps");
      }
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
        // Bitrate has already been handled above when modifying the SDP
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
  _remoteSDPs.remove(remoteUuid); // Clean up stored remote SDP
  _lowBitrateCount.remove(remoteUuid); // Clean up bitrate tracking
  _peerBitrates.remove(remoteUuid); // Clean up per-peer bitrate
  
  // Clear sdpBitrate when cleaning up the last connection
  if (_sessions.isEmpty) {
    print("Last peer connection closed, clearing sdpBitrate");
    sdpBitrate = 0;
  }
  
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
      
      // Don't modify offer SDP - just use it as is
      print("DEBUG: Creating offer without modifying bitrate (will be set in answer)");
      
      // Use original offer without modification
      RTCSessionDescription modifiedOffer = RTCSessionDescription(s.sdp, s.type);
      
      // Set local description with modified SDP
      print("DEBUG: Setting local description with bitrate constraints...");
      await pc.setLocalDescription(modifiedOffer);
      print("DEBUG: Local description set successfully");
      
      // Prepare to send the offer
      print("DEBUG: Preparing to send offer");
      var request = <String, dynamic>{};
      request["UUID"] = remoteUuid;
      request["description"] = modifiedOffer.toMap(); // Use modified offer
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
            final currentTime = DateTime.now().millisecondsSinceEpoch;
            final previousStats = _networkStats[remoteUuid];
            
            _networkStats[remoteUuid] = {
              'bytesSent': bytesSent,
              'packetsSent': packetsSent,
              'packetsLost': packetsLost,
              'timestamp': currentTime,
            };
            
            // Calculate current bitrate if we have previous stats
            if (previousStats != null && previousStats['bytesSent'] != null) {
              final timeDiff = (currentTime - previousStats['timestamp']) / 1000.0; // seconds
              if (timeDiff > 0) {
                final bytesDiff = bytesSent - previousStats['bytesSent'];
                final currentBitrateKbps = (bytesDiff * 8 / timeDiff / 1000).round();
                
                // Check if current bitrate is significantly below target
                final targetBitrate = getTargetBitrate();
                if (currentBitrateKbps < targetBitrate * 0.7 && currentBitrateKbps > 0) {
                  print("Warning: Current bitrate ${currentBitrateKbps}kbps is below target ${targetBitrate}kbps for $remoteUuid");
                  
                  // If bitrate is too low for too long, trigger renegotiation
                  final lowBitrateCount = (_lowBitrateCount[remoteUuid] ?? 0) + 1;
                  _lowBitrateCount[remoteUuid] = lowBitrateCount;
                  
                  if (lowBitrateCount > 3) { // After 3 consecutive low readings
                    print("Triggering renegotiation due to persistent low bitrate");
                    _lowBitrateCount[remoteUuid] = 0;
                    final pc = _sessions[remoteUuid];
                    if (pc != null && pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
                      _triggerRenegotiation(remoteUuid, pc);
                    }
                  }
                } else {
                  _lowBitrateCount[remoteUuid] = 0; // Reset counter
                }
              }
            }
            
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
  
  bool startedMediaProjectionService = false;

  try {
    // Set up resolution based on quality setting
    String width = quality ? "1920" : "1280";
    String height = quality ? "1080" : "720";
    String frameRate = quality ? "30" : "30";
    
    late MediaStream stream;
    
    if (deviceID == "screen") {
      print("Requesting screen sharing...");

      // For Android 14+ (SDK 34+), start MediaProjection foreground service BEFORE requesting screen capture
      if (Platform.isAndroid) {
        print("Starting MediaProjection foreground service for Android 14+...");
        try {
          // Always initialize first (required before checking permissions)
          const androidConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: 'VDO.Ninja Screen Sharing',
            notificationText: 'Screen sharing is active',
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon: AndroidResource(
              name: 'ic_launcher',
              defType: 'mipmap',
            ),
          );

          final bool hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);

          if (hasPermissions) {
            if (!FlutterBackground.isBackgroundExecutionEnabled) {
              final bool enabled = await FlutterBackground.enableBackgroundExecution();
              if (enabled) {
                startedMediaProjectionService = true;
                print("MediaProjection foreground service started successfully");
                // Give the service time to fully initialize before screen capture
                await Future.delayed(const Duration(milliseconds: 500));
              } else {
                print("WARNING: Failed to enable background execution");
              }
            } else {
              print("Background execution already enabled");
              startedMediaProjectionService = true;
            }
          } else {
            print("WARNING: Background execution permissions not granted");
          }
        } catch (e) {
          print("Error starting foreground service: $e");
          print("Continuing without foreground service...");
        }
      }

      try {
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
          
          // Note: iOS system audio capture is not supported due to platform restrictions
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
            'audio': true, // Try to capture system audio on Android
          });
          
          // System audio is already included in the screen share above (audio: true)
          // Commenting out redundant _trySystemAudioCapture to avoid double permission prompt
          /*
          // Try to add system audio capture for Android
          if (Platform.isAndroid) {
            try {
              MediaStream? systemAudio = await _trySystemAudioCapture();
              if (systemAudio != null) {
                // Mix system audio with screen capture
                var audioTracks = systemAudio.getAudioTracks();
                if (audioTracks.isNotEmpty) {
                  await stream.addTrack(audioTracks.first);
                  print("Added system audio track to screen share");
                }
              }
            } catch (e) {
              print("Failed to add system audio to screen share: $e");
            }
          }
          */
        }
      } catch (e) {
        if (startedMediaProjectionService) {
          print("Stopping MediaProjection service due to screen capture failure...");
          try {
            const platform = MethodChannel('vdoninja/media_projection');
            await platform.invokeMethod('stopMediaProjectionService');
          } catch (stopError) {
            print("Error stopping MediaProjection service after failure: $stopError");
          }
          startedMediaProjectionService = false;
        }
        rethrow;
      }
    } else if (deviceID == "microphone") {
      print("Requesting audio-only...");
      
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': await _buildAdvancedAudioConstraints(audioDeviceId),
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
      
      // Get combined stream with advanced audio constraints
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': await _buildAdvancedAudioConstraints(audioDeviceId),
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

    if (startedMediaProjectionService) {
      print("Stopping MediaProjection service due to createStream failure...");
      try {
        const platform = MethodChannel('vdoninja/media_projection');
        await platform.invokeMethod('stopMediaProjectionService');
      } catch (stopError) {
        print("Error stopping MediaProjection service after createStream failure: $stopError");
      }
    }
    
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
    
    // Don't modify offer SDP - bitrate will be set in answer
    print("Creating offer without modifying bitrate (will be set in answer)");
    
    // Use original offer without modification
    RTCSessionDescription modifiedOffer = RTCSessionDescription(offer.sdp, offer.type);
    
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
	
int? _cachedAndroidSdkInt;

Future<int?> _getAndroidSdkInt() async {
  if (!Platform.isAndroid) {
    return null;
  }

  if (_cachedAndroidSdkInt != null) {
    return _cachedAndroidSdkInt;
  }

  try {
    const MethodChannel channel = MethodChannel('vdoninja/device_info');
    final Map<String, dynamic>? deviceData =
        await channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
    final dynamic sdkValue = deviceData?['androidVersion'];
    if (sdkValue is int) {
      _cachedAndroidSdkInt = sdkValue;
      return _cachedAndroidSdkInt;
    }
    if (sdkValue is num) {
      _cachedAndroidSdkInt = sdkValue.toInt();
      return _cachedAndroidSdkInt;
    }
  } catch (e) {
    print("Error retrieving Android SDK version: $e");
  }

  return null;
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

// Build advanced audio constraints optimized for USB devices
Future<Map<String, dynamic>> _buildAdvancedAudioConstraints(String audioDeviceId) async {
  Map<String, dynamic> baseConstraints = {
    'echoCancellation': false,
    'autoGainControl': false, // Disable for professional USB devices
    'noiseSuppression': false, // Let professional devices handle this
    'googEchoCancellation': false,
    'googAutoGainControl': false,
    'googNoiseSuppression': false,
  };

  if (audioDeviceId == "default") {
    return {
      'mandatory': {
        ...baseConstraints,
        // Enable processing for built-in mics
        'autoGainControl': true,
        'noiseSuppression': true,
        'googAutoGainControl': true,
        'googNoiseSuppression': true,
      }
    };
  } else {
    // For specific devices (likely USB), try to get high quality
    Map<String, dynamic> constraints = {
      'optional': [
        {'sourceId': audioDeviceId},
        // Try for higher sample rates first
        {'sampleRate': 48000},
        {'sampleRate': 44100},
        {'channelCount': 2}, // Stereo if available
        {'latency': 0.01}, // Low latency
        {'sampleSize': 16},
      ],
      'mandatory': baseConstraints,
    };

    // Try to detect if this might be a USB audio device
    try {
      var devices = await navigator.mediaDevices.enumerateDevices();
      var device = devices.firstWhere(
        (d) => d.deviceId == audioDeviceId && d.kind == 'audioinput', 
        orElse: () => MediaDeviceInfo(deviceId: '', label: '', kind: '')
      );
      
      if (device.label.toLowerCase().contains('usb') || 
          device.label.toLowerCase().contains('audio interface') ||
          device.label.toLowerCase().contains('scarlett') ||
          device.label.toLowerCase().contains('focusrite') ||
          device.label.toLowerCase().contains('zoom') ||
          device.label.toLowerCase().contains('presonus') ||
          device.label.toLowerCase().contains('behringer') ||
          device.label.toLowerCase().contains('motu') ||
          device.label.toLowerCase().contains('rme') ||
          device.label.toLowerCase().contains('steinberg')) {
        print("Detected professional USB audio device: ${device.label}");
        
        // For professional devices, prioritize quality over processing
        constraints['optional']!.insertAll(0, [
          {'sampleRate': 96000}, // Try highest quality first
          {'sampleRate': 88200},
          {'latency': 0.005}, // Even lower latency
          {'channelCount': 8}, // Multi-channel support
          {'channelCount': 4},
        ]);
      }
    } catch (e) {
      print("Error detecting USB audio device: $e");
    }

    return constraints;
  }
}

// System audio capture for screen sharing (Android)
Future<MediaStream?> _trySystemAudioCapture() async {
  if (!Platform.isAndroid) {
    print("System audio capture only supported on Android");
    return null;
  }

  try {
    // Try to get system audio via display media
    var stream = await navigator.mediaDevices.getDisplayMedia({
      'audio': {
        'mandatory': {
          'chromeMediaSource': 'system',
          'echoCancellation': false,
          'noiseSuppression': false,
          'autoGainControl': false,
        }
      },
      'video': false,
    });
    
    print("Successfully captured system audio");
    return stream;
  } catch (e) {
    print("System audio capture failed: $e");
    
    // Fallback: try MediaProjection API constraints
    try {
      var stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'chromeMediaSource': 'desktop',
            'chromeMediaSourceId': 'system_audio',
            'echoCancellation': false,
          }
        }
      });
      
      print("System audio captured via MediaProjection");
      return stream;
    } catch (e2) {
      print("MediaProjection system audio failed: $e2");
      return null;
    }
  }
}

  Future<void> _createAnswer(
      String remoteUuid, String sessionId, RTCPeerConnection pc) async {
		print("Creating Answer for $remoteUuid...");
		try {
		  RTCSessionDescription s =
			  await pc.createAnswer(_sdpConstraints); // Use defined constraints
		  print("Answer created. Processing SDP for bitrate...");
		  
		  // Apply bitrate to SDP before setting local description
		  String sdp = s.sdp!;
		  
		  // Check if the offer already specified a bitrate
		  final remoteSdp = _remoteSDPs[remoteUuid] ?? '';
		  final offerBitrate = CodecsHandler.parseBitrateFromSdp(remoteSdp);
		  
		  int targetBitrate;
		  if (offerBitrate != null && offerBitrate > 0) {
		    print("Offer specified bitrate: ${offerBitrate}kbps, respecting it in answer");
		    // Use the viewer's requested bitrate
		    targetBitrate = offerBitrate;
		    _peerBitrates[remoteUuid] = offerBitrate; // Store per-peer bitrate
		  } else {
		    print("Offer did not specify bitrate, using our default");
		    // Use our default bitrate
		    targetBitrate = customBitrate > 0 ? customBitrate : (quality ? 10000 : 6000);
		    _peerBitrates[remoteUuid] = targetBitrate; // Store our default for this peer
		  }
		  
		  if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
		    // Set minimum to 80% of target for more aggressive bitrate
		    final params = {'min': (targetBitrate * 0.8).round(), 'max': targetBitrate};
		    sdp = CodecsHandler.setVideoBitrates(sdp, params);
		    print("Modified answer SDP with bitrate: min=${params['min']}kbps, max=${params['max']}kbps");
		    
		    // Force resolution constraints
		    if (quality) {
		      sdp = sdp.replaceAll('a=rtpmap:96 VP8/90000', 
		                           'a=rtpmap:96 VP8/90000\r\na=fmtp:96 max-fs=8160;max-fr=30');
		    } else {
		      sdp = sdp.replaceAll('a=rtpmap:96 VP8/90000', 
		                           'a=rtpmap:96 VP8/90000\r\na=fmtp:96 max-fs=3600;max-fr=30');
		    }
		  }
		  
		  // Create modified description and set it
		  RTCSessionDescription modifiedAnswer = RTCSessionDescription(sdp, s.type);
		  await pc.setLocalDescription(modifiedAnswer);
		  print("Local description set for $remoteUuid with bitrate constraints.");

		  var request = <String, dynamic>{};
		  request["UUID"] = remoteUuid; // Target
		  request["description"] = modifiedAnswer.toMap(); // Use modified answer
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
    
    // Clear stored remote SDPs and bitrate tracking
    _remoteSDPs.clear();
    _lowBitrateCount.clear();
    _peerBitrates.clear();

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

      // Stop MediaProjection service if it was screen sharing on Android
      if (Platform.isAndroid && deviceID == "screen") {
        final int? sdkInt = await _getAndroidSdkInt();
        if (sdkInt == null || sdkInt >= 34) {
          print("Stopping MediaProjection service...");
          try {
            const platform = MethodChannel('vdoninja/media_projection');
            await platform.invokeMethod('stopMediaProjectionService');
            print("MediaProjection service stopped");
          } catch (e) {
            print("Error stopping MediaProjection service: $e");
          }
        }
      }
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
    
    // Apply to all active connections by triggering renegotiation
    for (var entry in _sessions.entries) {
      if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        int targetBitrate = getTargetBitrate();
        print("Triggering renegotiation to apply bitrate ${targetBitrate}kbps for ${entry.key}");
        await _triggerRenegotiation(entry.key, entry.value);
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

