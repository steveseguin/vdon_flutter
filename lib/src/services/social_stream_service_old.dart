// social_stream_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/websocket.dart';
import '../models/social_stream_config.dart';

class SocialStreamService {
  final SocialStreamConfig config;
  final Function(ChatMessage) onChatMessage;
  
  // WebSocket mode
  SimpleWebSocket? _webSocket;
  WebSocket? _rawWebSocket; // Raw WebSocket for Social Stream
  
  // WebRTC mode
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  bool _isConnected = false;
  
  SocialStreamService({
    required this.config,
    required this.onChatMessage,
  });
  
  bool get isConnected => _isConnected;
  
  Future<void> connect() async {
    print('[SocialStream] === CONNECT CALLED ===');
    print('[SocialStream] Enabled: ${config.enabled}');
    
    if (!config.enabled) {
      print('[SocialStream] Not enabled, skipping connection');
      return;
    }
    
    print('[SocialStream] Mode: ${config.mode}');
    print('[SocialStream] Session ID: ${config.sessionId}');
    print('[SocialStream] Password: ${config.password ?? "false"}');
    
    if (config.mode == ConnectionMode.websocket) {
      print('[SocialStream] Using WebSocket mode');
      await _connectWebSocket();
    } else {
      print('[SocialStream] Using WebRTC mode');
      await _connectWebRTC();
    }
  }
  
  Future<void> _connectWebSocket() async {
    try {
      print('[SocialStream-WS] Creating WebSocket instance');
      _webSocket = SimpleWebSocket();
      
      _webSocket!.onOpen = () {
        print('[SocialStream-WS] === WEBSOCKET CONNECTED ===');
        _isConnected = true;
        
        // Send join message as per the JavaScript example
        final joinMessage = {
          'join': config.sessionId,
          'out': 3,
          'in': 4,
        };
        
        print('[SocialStream-WS] Sending join message: ${jsonEncode(joinMessage)}');
        _webSocket!.send(jsonEncode(joinMessage));
      };
      
      _webSocket!.onMessage = (dynamic message) {
        print('[SocialStream-WS] === MESSAGE RECEIVED ===');
        print('[SocialStream-WS] Raw message: $message');
        
        try {
          final data = jsonDecode(message);
          print('[SocialStream-WS] Parsed data: $data');
          _handleWebSocketMessage(data);
        } catch (e) {
          print('[SocialStream-WS] Error parsing message: $e');
          print('[SocialStream-WS] Message was: $message');
        }
      };
      
      _webSocket!.onClose = (int code, String reason) {
        print('[SocialStream-WS] === WEBSOCKET CLOSED ===');
        print('[SocialStream-WS] Code: $code, Reason: $reason');
        _isConnected = false;
      };
      
      // Connect to Social Stream WebSocket server
      final wsUrl = 'wss://io.socialstream.ninja';
      print('[SocialStream-WS] Connecting to: $wsUrl');
      print('[SocialStream-WS] Session: ${config.sessionId}');
      
      // Note: SimpleWebSocket sends a "seed" request which is VDO.Ninja specific
      // For Social Stream, we need a raw WebSocket connection
      print('[SocialStream-WS] WARNING: SimpleWebSocket may not be compatible with Social Stream');
      print('[SocialStream-WS] The \"seed\" request it sends is for VDO.Ninja, not Social Stream');
      
      // TODO: Replace with raw WebSocket implementation:
      // _rawWebSocket = await WebSocket.connect(wsUrl);
      // _rawWebSocket.listen((data) => _handleWebSocketMessage(jsonDecode(data)));
      // _rawWebSocket.add(jsonEncode({'join': config.sessionId, 'out': 3, 'in': 4}));
      
      await _webSocket!.connect(
        config.sessionId,
        wsUrl,
        '', // No UUID needed for Social Stream
      );
    } catch (e) {
      print('[SocialStream-WS] === CONNECTION ERROR ===');
      print('[SocialStream-WS] Error: $e');
      _isConnected = false;
    }
  }
  
  Future<void> _connectWebRTC() async {
    try {
      // Note: For proper WebRTC integration with Social Stream Ninja,
      // this should be integrated with the existing Signaling class
      // using the Social Stream handshake server: wss://wss.socialstream.ninja:443
      
      // Generate a random stream ID for our Social Stream viewer connection
      final random = Random();
      final chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
      final randomStreamId = String.fromCharCodes(Iterable.generate(
          8, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
      
      print('Social Stream WebRTC mode requires integration with Signaling class');
      print('Handshake server: wss://wss.socialstream.ninja:443');
      print('Stream ID (push): $randomStreamId'); // Our unique ID as a viewer
      print('View ID: ${config.sessionId}'); // The session we want to view/connect to
      print('Room ID: ${config.sessionId}'); // The room to join
      print('Label: dock');
      print('Password: ${config.password ?? "false"}');
      print('No audio/video, data channels only');
      
      // TODO: When integrating with Signaling class:
      // 1. Create a new Signaling instance with Social Stream parameters
      // 2. Use streamID = randomStreamId (our unique push ID)
      // 3. Use roomID = config.sessionId (the room we're joining)
      // 4. Use WSSADDRESS = 'wss://wss.socialstream.ninja:443'
      // 5. Use password = config.password ?? 'false'
      // 6. Set deviceID = 'datachannel' or similar to indicate no audio/video
      // 7. Set label = 'dock' in the initial info message
      // 8. Add view=${config.sessionId} to connect to the main app's stream
      // 9. Handle incoming data channel messages with 'overlayNinja' field
      
      _isConnected = false;
      print('WebRTC mode not yet fully integrated - use WebSocket mode for now');
      
    } catch (e) {
      print('Error setting up Social Stream WebRTC: $e');
      _isConnected = false;
    }
  }
  
  void _handleWebSocketMessage(Map<String, dynamic> data) {
    print('[SocialStream-WS] === HANDLING MESSAGE ===');
    print('[SocialStream-WS] Data type: ${data['type']}');
    print('[SocialStream-WS] Data action: ${data['action']}');
    print('[SocialStream-WS] Full data: $data');
    
    // Check for chat messages
    if (data['type'] == 'chat' || data['action'] == 'chat' || data.containsKey('chatmessage')) {
      print('[SocialStream-WS] Processing as chat message');
      final chatMessage = ChatMessage.fromSocialStream(data);
      print('[SocialStream-WS] Created ChatMessage: ${chatMessage.message} from ${chatMessage.username}');
      onChatMessage(chatMessage);
    } else {
      print('[SocialStream-WS] Not a chat message, type/action not recognized');
    }
  }
  
  void _handleWebRTCMessage(Map<String, dynamic> data) {
    if (data['type'] == 'chat') {
      final chatMessage = ChatMessage.fromSocialStream(data);
      onChatMessage(chatMessage);
    } else if (data['type'] == 'answer') {
      // Handle answer from Social Stream
      _handleAnswer(data['answer']);
    } else if (data['type'] == 'ice') {
      // Handle ICE candidate from Social Stream
      _handleIceCandidate(data['candidate']);
    }
  }
  
  Future<void> _handleAnswer(Map<String, dynamic> answer) async {
    try {
      final description = RTCSessionDescription(
        answer['sdp'],
        answer['type'],
      );
      await _peerConnection!.setRemoteDescription(description);
    } catch (e) {
      print('Error handling Social Stream answer: $e');
    }
  }
  
  Future<void> _handleIceCandidate(Map<String, dynamic> candidate) async {
    try {
      final iceCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(iceCandidate);
    } catch (e) {
      print('Error adding Social Stream ICE candidate: $e');
    }
  }
  
  void _sendSignalingMessage(Map<String, dynamic> message) {
    // For WebRTC mode, we need to send signaling through VDO.Ninja's WebSocket
    // This would be integrated with the main signaling service
    print('Social Stream signaling message: $message');
  }
  
  void disconnect() {
    _isConnected = false;
    
    if (_webSocket != null) {
      _webSocket!.close();
      _webSocket = null;
    }
    
    if (_dataChannel != null) {
      _dataChannel!.close();
      _dataChannel = null;
    }
    
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
  }
  
  void dispose() {
    disconnect();
  }
}

class ChatMessage {
  final String id;
  final String author;
  final String content;
  final DateTime timestamp;
  final String? avatarUrl;
  final String platform;
  final Map<String, dynamic>? metadata;
  
  ChatMessage({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    this.avatarUrl,
    this.platform = 'unknown',
    this.metadata,
  });
  
  factory ChatMessage.fromSocialStream(Map<String, dynamic> data) {
    print('[ChatMessage] === PARSING MESSAGE ===');
    print('[ChatMessage] Raw data: $data');
    
    // Check if data is wrapped in overlayNinja as per JavaScript examples
    Map<String, dynamic> messageData = data;
    if (data.containsKey('overlayNinja') && data['overlayNinja'] is Map) {
      print('[ChatMessage] Found overlayNinja wrapper');
      messageData = data['overlayNinja'] as Map<String, dynamic>;
    }
    
    // Extract fields based on JavaScript examples
    final id = messageData['mid'] ?? 
               messageData['id'] ?? 
               DateTime.now().millisecondsSinceEpoch.toString();
    
    final author = messageData['chatname'] ?? 
                   messageData['author'] ?? 
                   messageData['username'] ?? 
                   'Anonymous';
    
    final content = messageData['chatmessage'] ?? 
                    messageData['message'] ?? 
                    messageData['text'] ?? 
                    '';
    
    final avatarUrl = messageData['chatimg'] ?? 
                      messageData['avatar'] ?? 
                      messageData['profileImage'];
    
    final platform = messageData['type'] ?? 
                     messageData['platform'] ?? 
                     messageData['source'] ?? 
                     'unknown';
    
    print('[ChatMessage] Parsed - ID: $id, Author: $author, Content: $content, Platform: $platform');
    
    return ChatMessage(
      id: id.toString(),
      author: author.toString(),
      content: content.toString(),
      timestamp: messageData['timestamp'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(messageData['timestamp'])
        : DateTime.now(),
      avatarUrl: avatarUrl?.toString(),
      platform: platform.toString(),
      metadata: messageData,
    );
  }
}