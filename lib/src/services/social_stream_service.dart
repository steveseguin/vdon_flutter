// social_stream_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/social_stream_config.dart';

class SocialStreamService {
  final SocialStreamConfig config;
  final Function(ChatMessage) onChatMessage;
  
  // WebSocket mode
  WebSocket? _rawWebSocket; // Raw WebSocket for Social Stream
  
  // WebRTC mode
  Map<String, RTCPeerConnection> _peerConnections = {};
  Map<String, RTCDataChannel> _dataChannels = {};
  Map<String, List<RTCIceCandidate>> _pendingIceCandidates = {};
  Map<String, String> _peerSessions = {}; // Track session IDs for each peer
  Map<String, String> _browserUuidToStreamId = {}; // Map browser UUID to streamID
  Map<String, String> _peerConnectionMapping = {}; // Map actual browser UUID to our peer connection key
  String? _publisherBrowserUuid; // The browser's actual UUID from videoaddedtoroom
  // String? _streamId; // Our stream ID for WebRTC mode (not used in viewer mode)
  String? _uuid; // Our UUID for VDO.Ninja protocol (viewers use UUID, not streamID)
  
  bool _isConnected = false;
  
  // Reconnection logic
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 10;
  final int _initialReconnectDelay = 100; // Near instant for first attempt
  final int _baseReconnectDelay = 2000; // 2 seconds base delay
  final int _maxReconnectDelay = 10000; // 10 seconds max
  String? _persistentUuid; // Preserve UUID across reconnections
  Map<String, Timer> _closeTimeouts = {};
  Map<String, Timer> _heartbeatTimers = {}; // Per-connection heartbeat timers
  
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
    
    print('[SocialStream] === CONNECTION DETAILS ===');
    print('[SocialStream] Mode: ${config.mode}');
    print('[SocialStream] Session ID: ${config.sessionId}');
    print('[SocialStream] Password: ${config.password ?? "false"}');
    print('[SocialStream] ');
    print('[SocialStream] IMPORTANT: Make sure you are sending chat messages to');
    print('[SocialStream] the same session ID from your streaming software!');
    print('[SocialStream] ');
    print('[SocialStream] For OBS/Browser Source, use:');
    print('[SocialStream] https://socialstream.ninja/session/${config.sessionId}');
    print('[SocialStream] ');
    
    if (config.mode == ConnectionMode.websocket) {
      print('[SocialStream] Using WebSocket mode (Simple)');
      print('[SocialStream] Server: wss://io.socialstream.ninja');
      await _connectWebSocket();
    } else {
      print('[SocialStream] Using WebRTC mode (Low Latency)');
      print('[SocialStream] Server: wss://wss.socialstream.ninja');
      await _connectWebRTC();
    }
  }
  
  Future<void> _connectWebSocket() async {
    try {
      print('[SocialStream-WS] === STARTING WEBSOCKET CONNECTION ===');
      print('[SocialStream-WS] Mode: WebSocket (Simple)');
      
      // Connect to Social Stream WebSocket server
      final wsUrl = 'wss://io.socialstream.ninja';
      print('[SocialStream-WS] Server URL: $wsUrl');
      print('[SocialStream-WS] Session ID: ${config.sessionId}');
      print('[SocialStream-WS] This is different from main app which uses wss://wss.socialstream.ninja for WebRTC');
      
      _rawWebSocket = await WebSocket.connect(wsUrl);
      print('[SocialStream-WS] === WEBSOCKET CONNECTED SUCCESSFULLY ===');
      _isConnected = true;
      
      // Send join message as per the JavaScript example
      final joinMessage = {
        'join': config.sessionId,
        'out': 3,
        'in': 4,
      };
      
      print('[SocialStream-WS] Sending join message: ${jsonEncode(joinMessage)}');
      print('[SocialStream-WS] This joins room: ${config.sessionId}');
      print('[SocialStream-WS] Expecting to receive chat messages from this room');
      _rawWebSocket!.add(jsonEncode(joinMessage));
      
      // Send a test message after a short delay (for debugging)
      Timer(Duration(seconds: 2), () {
        if (_isConnected && _rawWebSocket != null) {
          print('[SocialStream-WS] === SENDING TEST MESSAGE ===');
          print('[SocialStream-WS] Note: This test message will only be received if');
          print('[SocialStream-WS] another client is also connected to session: ${config.sessionId}');
          print('[SocialStream-WS] ');
          print('[SocialStream-WS] To test, open in a browser:');
          print('[SocialStream-WS] https://socialstream.ninja/session/${config.sessionId}');
          print('[SocialStream-WS] ');
          
          final testMessage = {
            'action': 'send',
            'to': config.sessionId,
            'msg': {
              'chatname': 'Flutter Test',
              'chatmessage': 'Test message from Flutter app',
              'type': 'test',
            }
          };
          print('[SocialStream-WS] Test message: ${jsonEncode(testMessage)}');
          _rawWebSocket!.add(jsonEncode(testMessage));
        }
      });
      
      // Listen for messages
      _rawWebSocket!.listen(
        (dynamic message) {
          print('[SocialStream-WS] === MESSAGE RECEIVED ===');
          print('[SocialStream-WS] Raw message type: ${message.runtimeType}');
          print('[SocialStream-WS] Raw message: $message');
          print('[SocialStream-WS] Message length: ${message.toString().length}');
          
          try {
            Map<String, dynamic> data;
            if (message is String) {
              data = jsonDecode(message);
            } else {
              print('[SocialStream-WS] Message is not a string, attempting to convert');
              data = jsonDecode(message.toString());
            }
            print('[SocialStream-WS] Parsed data: $data');
            print('[SocialStream-WS] Data keys: ${data.keys.toList()}');
            
            // Check for join confirmation or error
            if (data.containsKey('joined')) {
              print('[SocialStream-WS] Successfully joined room: ${data['joined']}');
            } else if (data.containsKey('error')) {
              print('[SocialStream-WS] Error from server: ${data['error']}');
            }
            
            _handleWebSocketMessage(data);
          } catch (e) {
            print('[SocialStream-WS] Error parsing message: $e');
            print('[SocialStream-WS] Message was: $message');
          }
        },
        onDone: () {
          print('[SocialStream-WS] === WEBSOCKET CLOSED ===');
          _isConnected = false;
        },
        onError: (error) {
          print('[SocialStream-WS] === WEBSOCKET ERROR ===');
          print('[SocialStream-WS] Error: $error');
          _isConnected = false;
        },
        cancelOnError: false,
      );
      
    } catch (e) {
      print('[SocialStream-WS] === CONNECTION ERROR ===');
      print('[SocialStream-WS] Error: $e');
      _isConnected = false;
    }
  }
  
  Future<void> _connectWebRTC() async {
    try {
      print('[SocialStream-WebRTC] === STARTING WEBRTC MODE ===');
      
      print('[SocialStream-WebRTC] === VDO.NINJA PROTOCOL COMPLIANCE MODE ===');
      print('[SocialStream-WebRTC] Target room/session: ${config.sessionId}');
      print('[SocialStream-WebRTC] Mode: Viewer (data-channel only, label="dock")');
      
      // Connect to Social Stream WebRTC server
      final wsUrl = 'wss://wss.socialstream.ninja:443';
      print('[SocialStream-WebRTC] Server: $wsUrl');
      print('[SocialStream-WebRTC] Using VDO.Ninja protocol');
      print('[SocialStream-WebRTC] Connecting to: $wsUrl');
      
      _rawWebSocket = await WebSocket.connect(wsUrl);
      print('[SocialStream-WebRTC] === WEBSOCKET CONNECTED ===');
      print('[SocialStream-WebRTC] WebSocket state: ${_rawWebSocket!.readyState}');
      
      // Listen for messages
      _rawWebSocket!.listen(
        (dynamic message) {
          print('[SocialStream-WebRTC] Raw WebSocket message received, type: ${message.runtimeType}');
          _handleWebRTCSignaling(message);
        },
        onDone: () {
          print('[SocialStream-WebRTC] WebSocket closed');
          print('[SocialStream-WebRTC] Close code: ${_rawWebSocket?.closeCode}');
          print('[SocialStream-WebRTC] Close reason: ${_rawWebSocket?.closeReason}');
          _isConnected = false;
          
          // Schedule reconnection (similar to VDO.Ninja)
          if (config.enabled) {
            _scheduleReconnect();
          }
        },
        onError: (error) {
          print('[SocialStream-WebRTC] WebSocket error: $error');
          print('[SocialStream-WebRTC] Error type: ${error.runtimeType}');
          _isConnected = false;
          
          // Schedule reconnection on error
          if (config.enabled) {
            _scheduleReconnect();
          }
        },
        cancelOnError: false,
      );
      
      // Wait a moment for WebSocket to be fully ready
      await Future.delayed(Duration(milliseconds: 100));
      
      // First join the room
      final joinMessage = {
        'request': 'joinroom',
        'roomid': config.sessionId,
      };
      
      print('[SocialStream-WebRTC] Step 1: Joining room: ${config.sessionId}');
      print('[SocialStream-WebRTC] Message: ${jsonEncode(joinMessage)}');
      _rawWebSocket!.add(jsonEncode(joinMessage));
      
    } catch (e) {
      print('[SocialStream-WebRTC] Error: $e');
      _isConnected = false;
    }
  }
  
  void _handleWebSocketMessage(Map<String, dynamic> data) {
    print('[SocialStream-WS] === HANDLING MESSAGE ===');
    print('[SocialStream-WS] Data type: ${data['type']}');
    print('[SocialStream-WS] Data action: ${data['action']}');
    print('[SocialStream-WS] Full data: $data');
    
    // Check for various chat message formats
    bool isChatMessage = false;
    
    // Check for direct chat message fields
    if (data['type'] == 'chat' || 
        data['action'] == 'chat' || 
        data.containsKey('chatmessage') ||
        data.containsKey('chatname') ||
        data.containsKey('msg') ||
        data.containsKey('message')) {
      isChatMessage = true;
    }
    
    // Check for overlayNinja wrapper
    if (data.containsKey('overlayNinja') && data['overlayNinja'] is Map) {
      final overlayData = data['overlayNinja'] as Map<String, dynamic>;
      if (overlayData.containsKey('chatmessage') || 
          overlayData.containsKey('chatname') ||
          overlayData['type'] == 'chat') {
        isChatMessage = true;
      }
    }
    
    // Check for msg field (another common format)
    if (data.containsKey('msg') && data['msg'] is Map) {
      final msgData = data['msg'] as Map<String, dynamic>;
      if (msgData.containsKey('chatmessage') || msgData.containsKey('text')) {
        isChatMessage = true;
      }
    }
    
    if (isChatMessage) {
      print('[SocialStream-WS] Processing as chat message');
      try {
        final chatMessage = ChatMessage.fromSocialStream(data);
        print('[SocialStream-WS] Created ChatMessage: "${chatMessage.message}" from "${chatMessage.username}"');
        
        // Skip empty messages
        if (chatMessage.message.isEmpty) {
          print('[SocialStream-WS] Skipping empty message after HTML stripping');
          return;
        }
        
        print('[SocialStream-WS] Calling onChatMessage callback...');
        onChatMessage(chatMessage);
      } catch (e) {
        print('[SocialStream-WS] Error creating ChatMessage: $e');
      }
    } else {
      print('[SocialStream-WS] Not a chat message, available keys: ${data.keys.toList()}');
    }
  }
  
  void _handleWebRTCSignaling(dynamic message) {
    print('[SocialStream-WebRTC] === SIGNALING MESSAGE ===');
    print('[SocialStream-WebRTC] Raw message: $message');
    
    try {
      Map<String, dynamic> data;
      if (message is String) {
        data = jsonDecode(message);
      } else {
        data = jsonDecode(message.toString());
      }
      
      print('[SocialStream-WebRTC] Parsed data: $data');
      
      // Handle VDO.Ninja protocol messages
      if (data['request'] == 'listing') {
        print('[SocialStream-WebRTC] === ROOM LISTING RECEIVED ===');
        final list = data['list'] ?? [];
        print('[SocialStream-WebRTC] Found ${list.length} peers in room');
        print('[SocialStream-WebRTC] Peer list: ${jsonEncode(list)}');
        
        print('[SocialStream-WebRTC] Room has ${list.length} peers');
        
        // Generate our UUID using VDO.Ninja compatible format
        // Reuse persistent UUID if reconnecting
        if (_persistentUuid != null && _reconnectAttempts > 0) {
          _uuid = _persistentUuid;
          print('[SocialStream-WebRTC] Reusing UUID for reconnection: $_uuid');
        } else {
          var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
          Random rnd = Random();
          _uuid = String.fromCharCodes(Iterable.generate(
              16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
          _persistentUuid = _uuid; // Store for reconnections
          print('[SocialStream-WebRTC] Generated new UUID: $_uuid');
        }
        
        // Seed ourselves as a viewer that can receive data
        final seedMessage = {
          'request': 'seed',
          'streamID': _uuid,
          'room': config.sessionId,
          'view': true,  // Indicate we're a viewer
          'noaudio': true,
          'novideo': true,
          'label': 'dock',  // Important: Social Stream expects 'dock' label
        };
        
        print('[SocialStream-WebRTC] Seeding as viewer with UUID: $_uuid and label: "dock"');
        _rawWebSocket!.add(jsonEncode(seedMessage));
        
        // Wait for seed confirmation, then announce ourselves and request to view
        Timer(Duration(milliseconds: 500), () {
          // Announce ourselves to the room
          final videoAddedMsg = {
            'request': 'videoaddedtoroom',
            'UUID': _uuid,
            'streamID': _uuid,
            'room': config.sessionId,
          };
          print('[SocialStream-WebRTC] Announcing ourselves to room: ${jsonEncode(videoAddedMsg)}');
          _rawWebSocket!.add(jsonEncode(videoAddedMsg));
          
          // Then request to view peers
          _requestToViewPeers(list);
        });
        
        // The peer viewing is now handled by _requestToViewPeers
        
      } else if (data['request'] == 'play') {
        print('[SocialStream-WebRTC] === PLAY REQUEST ACCEPTED ===');
        print('[SocialStream-WebRTC] Can now receive from: ${data['streamID']}');
        print('[SocialStream-WebRTC] Full play response: ${jsonEncode(data)}');
        _isConnected = true;
        
        // In some cases, we might need to push to the publisher
        if (data['push'] == true || data['needpush'] == true) {
          print('[SocialStream-WebRTC] Publisher needs us to push');
          // We might need to create an offer instead of waiting for one
        }
        
      } else if (data['request'] == 'seed') {
        print('[SocialStream-WebRTC] === SEED RESPONSE ===');
        print('[SocialStream-WebRTC] Seed response data: ${jsonEncode(data)}');
        
        // Check if this is someone else's seed
        if (data['streamID'] != null && data['streamID'] != _uuid) {
          print('[SocialStream-WebRTC] Another peer seeded with streamID: ${data['streamID']}');
          
          // If another peer joined, we might need to notify them about us
          if (_uuid != null && _isConnected) {
            print('[SocialStream-WebRTC] Notifying new peer about our presence');
            // Send a notification that we exist
            final notifyMsg = {
              'request': 'videoaddedtoroom',
              'UUID': _uuid,
              'streamID': _uuid,
              'room': config.sessionId,
            };
            print('[SocialStream-WebRTC] Sending notification: ${jsonEncode(notifyMsg)}');
            _rawWebSocket!.add(jsonEncode(notifyMsg));
          }
          return;
        }
        
        if (data.containsKey('UUID') && data['UUID'] != null) {
          // Server assigned us a UUID
          _uuid = data['UUID'];
          _persistentUuid = _uuid; // Store for reconnections
          print('[SocialStream-WebRTC] Server assigned UUID: $_uuid');
          _isConnected = true;
          _reconnectAttempts = 0; // Reset on successful connection
        } else if (data.containsKey('streamID') && data['streamID'] != null) {
          // Sometimes it's in streamID field
          _uuid = data['streamID'];
          _persistentUuid = _uuid; // Store for reconnections
          print('[SocialStream-WebRTC] Server assigned streamID: $_uuid');
          _isConnected = true;
          _reconnectAttempts = 0; // Reset on successful connection
        } else {
          print('[SocialStream-WebRTC] WARNING: No UUID/streamID in seed response');
          print('[SocialStream-WebRTC] Available keys: ${data.keys.toList()}');
        }
        
      } else if (data.containsKey('joined')) {
        print('[SocialStream-WebRTC] === JOINED ROOM (Social Stream format) ===');
        print('[SocialStream-WebRTC] Room: ${data['joined']}');
        
      } else if (data['request'] == 'joinedRoom') {
        print('[SocialStream-WebRTC] === JOINED ROOM SUCCESSFULLY ===');
        print('[SocialStream-WebRTC] Room: ${data['roomid'] ?? data['room']}');
        _isConnected = true;
        
        // Step 2: After joining, request the list of peers
        final listMessage = {
          'UUID': _uuid,
          'request': 'list',
        };
        print('[SocialStream-WebRTC] Step 2: Requesting peer list');
        print('[SocialStream-WebRTC] Message: ${jsonEncode(listMessage)}');
        _rawWebSocket!.add(jsonEncode(listMessage));
        
      } else if (data['request'] == 'list') {
        // This is a response to a manual list request
        print('[SocialStream-WebRTC] === MANUAL LIST RESPONSE ===');
        final list = data['list'] ?? [];
        print('[SocialStream-WebRTC] Peers in room: $list');
        
      } else if (data['request'] == 'rpush' || data['rpush'] != null) {
        print('[SocialStream-WebRTC] === RPUSH MESSAGE ===');
        print('[SocialStream-WebRTC] Browser is pushing to us');
        print('[SocialStream-WebRTC] rpush data: ${jsonEncode(data)}');
        if (data['UUID'] != null) {
          // Update the publisher browser UUID
          _publisherBrowserUuid = data['UUID'];
          print('[SocialStream-WebRTC] Updated publisher browser UUID: $_publisherBrowserUuid');
        }
        
      } else if (data['request'] == 'playStream') {
        print('[SocialStream-WebRTC] === PLAY STREAM ACCEPTED ===');
        print('[SocialStream-WebRTC] Can now receive from peer: ${data['streamID']}');
        
      } else if (data['request'] == 'offerSDP') {
        print('[SocialStream-WebRTC] === OFFER REQUESTED ===');
        print('[SocialStream-WebRTC] Peer ${data['UUID']} wants us to create an offer');
        print('[SocialStream-WebRTC] Full offerSDP request: ${jsonEncode(data)}');
        
        // The browser wants us to create an offer - this means we need to push to it
        final targetUuid = data['UUID'];
        if (targetUuid != null) {
          print('[SocialStream-WebRTC] Browser wants us to push - creating offer for: $targetUuid');
          _createOffer(targetUuid);
        }
        
      } else if (data['description'] != null) {
        final sdpType = data['description']['type'];
        final fromUuid = data['UUID'] ?? data['streamID'] ?? 'unknown';
        print('[SocialStream-WebRTC] === SDP RECEIVED ===');
        print('[SocialStream-WebRTC] Type: $sdpType from: $fromUuid');
        print('[SocialStream-WebRTC] Message keys: ${data.keys.toList()}');
        
        // Check all possible UUID fields
        if (data.containsKey('UUID')) print('[SocialStream-WebRTC] UUID field: ${data['UUID']}');
        if (data.containsKey('streamID')) print('[SocialStream-WebRTC] streamID field: ${data['streamID']}');
        if (data.containsKey('session')) print('[SocialStream-WebRTC] session field: ${data['session']}');
        
        // Check browser UUID mapping for this peer
        if (data.containsKey('UUID') && _browserUuidToStreamId.containsKey(data['UUID'])) {
          print('[SocialStream-WebRTC] This UUID maps to streamID: ${_browserUuidToStreamId[data['UUID']]}');
        }
        if (data.containsKey('streamID') && _browserUuidToStreamId.containsKey(data['streamID'])) {
          print('[SocialStream-WebRTC] This streamID maps to UUID: ${_browserUuidToStreamId[data['streamID']]}');
        }
        
        if (sdpType == 'offer') {
          // Handle incoming offer from publisher
          _handleIncomingOffer(data);
        } else if (sdpType == 'answer') {
          // Handle answer to our offer
          _handleSDP(data);
        }
        
      } else if (data['candidate'] != null) {
        print('[SocialStream-WebRTC] === ICE CANDIDATE ===');
        print('[SocialStream-WebRTC] From: ${data['UUID'] ?? data['streamID'] ?? 'unknown'}');
        print('[SocialStream-WebRTC] ICE candidate data: ${jsonEncode(data)}');
        _handleIceCandidate(data);
        
      } else if (data['candidates'] != null) {
        // Handle batch of ICE candidates
        print('[SocialStream-WebRTC] === ICE CANDIDATES BATCH ===');
        print('[SocialStream-WebRTC] Received ${data['candidates'].length} candidates from: ${data['UUID'] ?? data['streamID']}');
        for (var candidate in data['candidates']) {
          _handleIceCandidate({
            'UUID': data['UUID'] ?? data['streamID'],
            'candidate': candidate,
          });
        }
        
      } else if (data['request'] == 'videoaddedtoroom') {
        print('[SocialStream-WebRTC] === VIDEO ADDED TO ROOM ===');
        print('[SocialStream-WebRTC] Browser UUID: ${data['UUID']}');
        print('[SocialStream-WebRTC] Browser streamID: ${data['streamID']}');
        
        // Store the browser's actual UUID for ICE candidate routing
        final browserUuid = data['UUID'];
        final browserStreamId = data['streamID'];
        
        // Store the publisher's browser UUID
        _publisherBrowserUuid = browserUuid;
        print('[SocialStream-WebRTC] Publisher browser UUID: $_publisherBrowserUuid');
        
        // Store the mapping both ways
        _browserUuidToStreamId[browserUuid] = browserStreamId;
        _browserUuidToStreamId[browserStreamId] = browserUuid; // Reverse mapping
        print('[SocialStream-WebRTC] Stored mapping: UUID $browserUuid <-> streamID $browserStreamId');
        
        // Request to view this stream
        Timer(Duration(milliseconds: 500), () {
          final viewMessage = {
            'request': 'play',
            'streamID': browserStreamId,
          };
          print('[SocialStream-WebRTC] Requesting to view browser stream: $browserStreamId');
          _rawWebSocket!.add(jsonEncode(viewMessage));
        });
        
      } else if (data['request'] == 'seed' && data['streamID'] != _uuid) {
        print('[SocialStream-WebRTC] === NEW PEER JOINED ===');
        print('[SocialStream-WebRTC] Peer streamID: ${data['streamID']}');
        
        // A new peer joined, request to view their stream
        final peerStreamId = data['streamID'];
        Timer(Duration(seconds: 1), () {
          final viewMessage = {
            'request': 'play',
            'streamID': peerStreamId,
            'room': config.sessionId,
          };
          print('[SocialStream-WebRTC] Requesting to view new peer: $peerStreamId');
          _rawWebSocket!.add(jsonEncode(viewMessage));
        });
        
      } else if (data['request'] == 'close' || data['request'] == 'disconnect') {
        print('[SocialStream-WebRTC] === PEER DISCONNECTED ===');
        final peerUuid = data['UUID'] ?? data['streamID'];
        if (peerUuid != null) {
          print('[SocialStream-WebRTC] Peer $peerUuid disconnected');
          // Clean up peer connection
          if (_peerConnections.containsKey(peerUuid)) {
            _peerConnections[peerUuid]!.close();
            _peerConnections.remove(peerUuid);
            _dataChannels.remove(peerUuid);
            _peerSessions.remove(peerUuid);
            _pendingIceCandidates.remove(peerUuid);
          }
        }
        
      } else if (data['info'] != null) {
        print('[SocialStream-WebRTC] === INFO MESSAGE ===');
        print('[SocialStream-WebRTC] ${data['info']}');
        
      } else if (data['error'] != null) {
        print('[SocialStream-WebRTC] === ERROR MESSAGE ===');
        print('[SocialStream-WebRTC] ${data['error']}');
        
      } else {
        print('[SocialStream-WebRTC] === UNKNOWN MESSAGE ===');
        print('[SocialStream-WebRTC] Keys: ${data.keys.toList()}');
        
        // Don't log full message if it's too large (like SDP)
        if (jsonEncode(data).length > 1000) {
          print('[SocialStream-WebRTC] Message too large to log fully');
          // Log just the structure
          final summary = Map<String, dynamic>.from(data);
          if (summary.containsKey('description')) {
            summary['description'] = '... SDP content ...';
          }
          print('[SocialStream-WebRTC] Message summary: ${jsonEncode(summary)}');
        } else {
          print('[SocialStream-WebRTC] Full message: ${jsonEncode(data)}');
        }
        
        // Check if this is our UUID assignment
        if (data.containsKey('UUID') && _uuid == null) {
          _uuid = data['UUID'];
          print('[SocialStream-WebRTC] UUID assigned by server: $_uuid');
        }
        
        // Check if this is a direct peer notification
        if (data.containsKey('UUID') && !data.containsKey('request')) {
          print('[SocialStream-WebRTC] Possible peer notification');
          // This might be the browser identifying itself
          if (data.containsKey('streamID') && data['streamID'] == config.sessionId) {
            _publisherBrowserUuid = data['UUID'];
            print('[SocialStream-WebRTC] Captured browser UUID from peer notification: $_publisherBrowserUuid');
          }
        }
        
        // Check for any message that might contain the browser's UUID
        if (data.containsKey('UUID') && data.containsKey('streamID')) {
          // If we see a message with both UUID and streamID matching our session
          if (data['streamID'] == config.sessionId && _publisherBrowserUuid == null) {
            _publisherBrowserUuid = data['UUID'];
            print('[SocialStream-WebRTC] Captured browser UUID from message: $_publisherBrowserUuid');
          }
        }
      }
      
    } catch (e) {
      print('[SocialStream-WebRTC] Error parsing signaling message: $e');
    }
  }
  
  // Create offer when browser requests it
  Future<void> _createOffer(String uuid) async {
    try {
      print('[SocialStream-WebRTC] Creating peer connection for: $uuid');
      
      // Check if we already have a connection for this UUID
      if (_peerConnections.containsKey(uuid)) {
        print('[SocialStream-WebRTC] Peer connection already exists for: $uuid');
        return;
      }
      
      // Create peer connection
      final pcConfig = {
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'},
        ]
      };
      
      final pc = await createPeerConnection(pcConfig);
      _peerConnections[uuid] = pc;
      
      // Add data channel with 'dock' label for Social Stream
      final dataChannelConfig = RTCDataChannelInit();
      dataChannelConfig.ordered = true;
      dataChannelConfig.maxRetransmits = 3;
      final dc = await pc.createDataChannel('dock', dataChannelConfig);
      _dataChannels[uuid] = dc;
      
      print('[SocialStream-WebRTC] Created data channel with label: "dock"');
      
      dc.onMessage = (RTCDataChannelMessage message) {
        print('[SocialStream-WebRTC] === RAW DATA CHANNEL MESSAGE ===');
        print('[SocialStream-WebRTC] From: $uuid');
        print('[SocialStream-WebRTC] Message type: ${message.isBinary ? "binary" : "text"}');
        print('[SocialStream-WebRTC] Raw text: ${message.text}');
        print('[SocialStream-WebRTC] Text length: ${message.text.length}');
        
        // Try to parse as JSON
        try {
          final data = jsonDecode(message.text);
          print('[SocialStream-WebRTC] Successfully parsed as JSON');
          _handleDataChannelMessage(uuid, data);
        } catch (e) {
          print('[SocialStream-WebRTC] Failed to parse as JSON: $e');
          print('[SocialStream-WebRTC] First 200 chars: ${message.text.substring(0, message.text.length > 200 ? 200 : message.text.length)}');
          
          // Try to handle as plain text message
          print('[SocialStream-WebRTC] Attempting to handle as plain text chat message');
          final chatMessage = ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            username: 'DataChannel User',
            message: message.text,
            timestamp: DateTime.now(),
            platform: 'datachannel',
          );
          onChatMessage(chatMessage);
        }
      };
      
      dc.onDataChannelState = (RTCDataChannelState state) {
        print('[SocialStream-WebRTC] Data channel state for $uuid: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          print('[SocialStream-WebRTC] === DATA CHANNEL OPENED ===');
          print('[SocialStream-WebRTC] Ready to receive messages from: $uuid');
          
          // Send initial info message to confirm data channel is ready
          _sendDataChannelInfo(uuid);
        }
      };
      
      // Handle ICE candidates (VDO.Ninja format)
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate != null) {
          final candidateMsg = {
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMLineIndex': candidate.sdpMLineIndex,
              'sdpMid': candidate.sdpMid,
            },
            'UUID': uuid,  // Browser's UUID (it will look in pcs[UUID])
            'type': 'remote',  // remote = from remote peer (us) to browser
          };
          
          // Include session if we have it
          if (_peerSessions.containsKey(uuid)) {
            candidateMsg['session'] = _peerSessions[uuid]!;
          }
          print('[SocialStream-WebRTC] Sending ICE candidate (from offer):');
          print('[SocialStream-WebRTC]   Our UUID: $_uuid');
          print('[SocialStream-WebRTC]   Target: $uuid');
          _rawWebSocket!.add(jsonEncode(candidateMsg));
        }
      };
      
      // Handle incoming data channels (when remote peer creates them)
      pc.onDataChannel = (RTCDataChannel channel) {
        print('[SocialStream-WebRTC] Incoming data channel from $uuid: ${channel.label}');
        if (channel.label == 'dock') {
          print('[SocialStream-WebRTC] ✅ Correct label "dock" detected - Social Stream chat channel');
        } else {
          print('[SocialStream-WebRTC] ⚠️  Warning: Expected label "dock" but got "${channel.label}"');
        }
        _dataChannels[uuid] = channel;
        
        channel.onMessage = (RTCDataChannelMessage message) {
          print('[SocialStream-WebRTC] === RAW INCOMING CHANNEL MESSAGE ===');
          print('[SocialStream-WebRTC] From: $uuid');
          print('[SocialStream-WebRTC] Channel label: ${channel.label}');
          print('[SocialStream-WebRTC] Message type: ${message.isBinary ? "binary" : "text"}');
          print('[SocialStream-WebRTC] Raw text: ${message.text}');
          print('[SocialStream-WebRTC] Text length: ${message.text.length}');
          
          try {
            final data = jsonDecode(message.text);
            print('[SocialStream-WebRTC] Successfully parsed as JSON');
            _handleDataChannelMessage(uuid, data);
          } catch (e) {
            print('[SocialStream-WebRTC] Failed to parse as JSON: $e');
            print('[SocialStream-WebRTC] First 200 chars: ${message.text.substring(0, message.text.length > 200 ? 200 : message.text.length)}');
            
            // Try to handle as plain text message
            print('[SocialStream-WebRTC] Attempting to handle as plain text chat message');
            final chatMessage = ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              username: 'DataChannel User',
              message: message.text,
              timestamp: DateTime.now(),
              platform: 'datachannel',
            );
            onChatMessage(chatMessage);
          }
        };
        
        channel.onDataChannelState = (RTCDataChannelState state) {
          print('[SocialStream-WebRTC] Incoming channel state for $uuid: $state');
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            print('[SocialStream-WebRTC] === INCOMING DATA CHANNEL OPENED ===');
            print('[SocialStream-WebRTC] Ready to receive messages on channel: ${channel.label}');
            
            // Send initial info message to confirm data channel is ready
            _sendDataChannelInfo(uuid);
          }
        };
      };
      
      // Create offer
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      
      // Send offer (VDO.Ninja format)
      final offerMsg = {
        'description': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'UUID': uuid,  // Target peer UUID
        'streamID': _uuid,  // Our stream ID
        'from': _uuid,  // Our UUID - important for browser to identify us
      };
      
      // Include session if we have it
      if (_peerSessions.containsKey(uuid)) {
        offerMsg['session'] = _peerSessions[uuid]!;
      }
      
      print('[SocialStream-WebRTC] Sending offer to peer: $uuid');
      print('[SocialStream-WebRTC] Offer message: ${jsonEncode(offerMsg)}');
      _rawWebSocket!.add(jsonEncode(offerMsg));
      
    } catch (e) {
      print('[SocialStream-WebRTC] Error creating offer: $e');
    }
  }
  
  Future<void> _handleIncomingOffer(Map<String, dynamic> data) async {
    try {
      // VDO.Ninja might use either UUID or streamID
      final uuid = data['UUID'] ?? data['streamID'];
      if (uuid == null) {
        print('[SocialStream-WebRTC] No UUID/streamID in offer');
        return;
      }
      
      // Check if we have a browser UUID mapping
      String? actualBrowserUuid;
      print('[SocialStream-WebRTC] Checking browser UUID mappings: ${_browserUuidToStreamId}');
      for (var entry in _browserUuidToStreamId.entries) {
        if (entry.value == uuid || entry.key == uuid) {
          actualBrowserUuid = entry.key;
          print('[SocialStream-WebRTC] Found browser UUID mapping: $actualBrowserUuid -> ${entry.value}');
          break;
        }
      }
      
      // Store the session ID if provided
      if (data['session'] != null) {
        _peerSessions[uuid] = data['session'];
        print('[SocialStream-WebRTC] Stored session ID for peer $uuid: ${data['session']}');
        // Also store for actual browser UUID if different
        if (actualBrowserUuid != null && actualBrowserUuid != uuid) {
          _peerSessions[actualBrowserUuid] = data['session'];
        }
      }
      
      print('[SocialStream-WebRTC] Handling incoming offer from: $uuid');
      if (actualBrowserUuid != null && actualBrowserUuid != uuid) {
        print('[SocialStream-WebRTC] Actual browser UUID: $actualBrowserUuid');
      }
      print('[SocialStream-WebRTC] My UUID: $_uuid');
      
      if (_uuid == null) {
        print('[SocialStream-WebRTC] ERROR: Our UUID is null! Cannot send proper answer.');
        print('[SocialStream-WebRTC] This will cause "ICE DID NOT FIND A PC OPTION" error.');
        // Generate a temporary UUID for this session using VDO.Ninja format
        var chars = 'AaBbCcDdEeFfGgHhJjKkLMmNnoPpQqRrSsTtUuVvWwXxYyZz23456789';
        Random rnd = Random();
        _uuid = String.fromCharCodes(Iterable.generate(
            16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
        print('[SocialStream-WebRTC] Generated temporary UUID: $_uuid');
      }
      
      // Store the browser's UUID from the offer
      if (_publisherBrowserUuid == null && data.containsKey('streamID')) {
        // The streamID in the offer might be the browser's actual UUID
        _publisherBrowserUuid = data['streamID'];
        print('[SocialStream-WebRTC] Captured browser UUID from offer streamID: $_publisherBrowserUuid');
      }
      
      // Create peer connection if it doesn't exist
      if (!_peerConnections.containsKey(uuid)) {
        final pcConfig = {
          'iceServers': [
            {'url': 'stun:stun.l.google.com:19302'},
          ]
        };
        
        final pc = await createPeerConnection(pcConfig);
        _peerConnections[uuid] = pc;
        
        // Monitor connection state with VDO.Ninja-style handling
        pc.onConnectionState = (RTCPeerConnectionState state) {
          print('[SocialStream-WebRTC] Connection state for $uuid: $state');
          
          switch (state) {
            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              print('[SocialStream-WebRTC] === PEER CONNECTION ESTABLISHED ===');
              print('[SocialStream-WebRTC] Connected to: $uuid');
              _cancelCloseTimeout(uuid);
              _reconnectAttempts = 0; // Reset on successful connection
              break;
              
            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              // Platform-specific timeout (VDO.Ninja uses 10s for Windows, 5s for others)
              final timeout = Platform.isWindows ? 10000 : 5000;
              print('[SocialStream-WebRTC] Connection disconnected - scheduling $timeout ms timeout');
              _scheduleCloseTimeout(uuid, timeout);
              break;
              
            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              print('[SocialStream-WebRTC] Connection failed - attempting recovery');
              _handleConnectionFailure(uuid);
              break;
              
            case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
              _cleanupPeerConnection(uuid);
              break;
              
            default:
              break;
          }
        };
        
        // Handle ICE candidates (VDO.Ninja format)
        pc.onIceCandidate = (RTCIceCandidate candidate) {
          if (candidate != null) {
            // For ICE candidates, use the peer's UUID from the offer
            String targetUuid = uuid;
            
            final candidateMsg = {
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMLineIndex': candidate.sdpMLineIndex,
                'sdpMid': candidate.sdpMid,
              },
              'UUID': uuid,  // Browser's UUID (it will look in pcs[UUID])
              'type': 'remote',  // remote = from remote peer (us) to browser
            };
            
            // Include session if we have it (official WSS mode)
            if (_peerSessions.containsKey(uuid)) {
              candidateMsg['session'] = _peerSessions[uuid]!;
            }
            print('[SocialStream-WebRTC] Sending ICE candidate:');
            print('[SocialStream-WebRTC]   UUID: $uuid');
            if (_peerSessions.containsKey(uuid)) {
              print('[SocialStream-WebRTC]   Session: ${_peerSessions[uuid]}');
            }
            _rawWebSocket!.add(jsonEncode(candidateMsg));
          }
        };
        
        // Handle incoming data channels
        pc.onDataChannel = (RTCDataChannel channel) {
          print('[SocialStream-WebRTC] Incoming data channel from $uuid: ${channel.label}');
        if (channel.label == 'dock') {
          print('[SocialStream-WebRTC] ✅ Correct label "dock" detected - Social Stream chat channel');
        } else {
          print('[SocialStream-WebRTC] ⚠️  Warning: Expected label "dock" but got "${channel.label}"');
        }
          _dataChannels[uuid] = channel;
          
          channel.onMessage = (RTCDataChannelMessage message) {
            print('[SocialStream-WebRTC] Incoming channel message from $uuid: ${message.text}');
            try {
              final data = jsonDecode(message.text);
              _handleDataChannelMessage(uuid, data);
            } catch (e) {
              print('[SocialStream-WebRTC] Error parsing incoming channel message: $e');
            }
          };
          
          channel.onDataChannelState = (RTCDataChannelState state) {
            print('[SocialStream-WebRTC] Incoming channel state for $uuid: $state');
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              print('[SocialStream-WebRTC] === INCOMING DATA CHANNEL OPENED (from offer) ===');
              print('[SocialStream-WebRTC] Ready to receive messages on channel: ${channel.label}');
              
              // Send initial info message to confirm data channel is ready
              _sendDataChannelInfo(uuid);
            }
          };
        };
      }
      
      // Set remote description
      final description = RTCSessionDescription(
        data['description']['sdp'],
        data['description']['type'],
      );
      await _peerConnections[uuid]!.setRemoteDescription(description);
      
      // Process any pending ICE candidates now that we have remote description
      await _processPendingIceCandidates(uuid);
      
      // Create answer
      final answer = await _peerConnections[uuid]!.createAnswer();
      await _peerConnections[uuid]!.setLocalDescription(answer);
      
      // Send answer (VDO.Ninja format)
      final answerMsg = {
        'description': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
        'UUID': uuid,  // Target peer UUID (who sent us the offer)
        'streamID': _uuid,  // Our stream ID
        'from': _uuid,  // Our UUID - important for browser to identify us
      };
      
      // Include session if we have it (from the offer)
      if (_peerSessions.containsKey(uuid)) {
        answerMsg['session'] = _peerSessions[uuid]!;
      }
      
      print('[SocialStream-WebRTC] Sending answer to: $uuid');
      if (_peerSessions.containsKey(uuid)) {
        print('[SocialStream-WebRTC]   Session: ${_peerSessions[uuid]}');
      }
      _rawWebSocket!.add(jsonEncode(answerMsg));
      
    } catch (e) {
      print('[SocialStream-WebRTC] Error handling incoming offer: $e');
    }
  }
  
  Future<void> _handleSDP(Map<String, dynamic> data) async {
    try {
      // The UUID might be in different fields
      final uuid = data['UUID'] ?? data['streamID'];
      if (uuid == null) {
        print('[SocialStream-WebRTC] No UUID/streamID in SDP message');
        return;
      }
      
      // Try to find the peer connection
      RTCPeerConnection? pc;
      String? connectionKey;
      
      if (_peerConnections.containsKey(uuid)) {
        pc = _peerConnections[uuid];
        connectionKey = uuid;
      } else {
        // Check if we have only one connection and use it
        if (_peerConnections.length == 1) {
          connectionKey = _peerConnections.keys.first;
          pc = _peerConnections[connectionKey];
          print('[SocialStream-WebRTC] Using only available peer connection for answer');
        }
      }
      
      if (pc == null || connectionKey == null) {
        print('[SocialStream-WebRTC] No peer connection found for UUID: $uuid');
        return;
      }
      
      final description = RTCSessionDescription(
        data['description']['sdp'],
        data['description']['type'],
      );
      
      if (description.type == 'answer') {
        await pc.setRemoteDescription(description);
        print('[SocialStream-WebRTC] Answer set successfully for: $connectionKey');
        
        // Process any pending ICE candidates
        await _processPendingIceCandidates(connectionKey);
      }
    } catch (e) {
      print('[SocialStream-WebRTC] Error handling SDP: $e');
    }
  }
  
  void _handleDataChannelMessage(String uuid, Map<String, dynamic> data) {
    print('[SocialStream-WebRTC] === DATA CHANNEL MESSAGE ===');
    print('[SocialStream-WebRTC] From peer: $uuid');
    print('[SocialStream-WebRTC] Message size: ${jsonEncode(data).length} bytes');
    
    // Special handling for dataReceived messages (Social Stream format)
    if (data.containsKey('dataReceived')) {
      print('[SocialStream-WebRTC] 🎯 SOCIAL STREAM MESSAGE DETECTED (dataReceived wrapper)');
    }
    
    print('[SocialStream-WebRTC] Raw data: $data');
    print('[SocialStream-WebRTC] Data type: ${data.runtimeType}');
    print('[SocialStream-WebRTC] Data keys: ${data.keys.toList()}');
    
    // Debug: Print each key-value pair
    data.forEach((key, value) {
      print('[SocialStream-WebRTC]   $key: ${value.runtimeType} = ${value.toString().length > 100 ? value.toString().substring(0, 100) + "..." : value}');
    });
    
    // VDO.Ninja protocol: Check for "msg" wrapper first
    if (data.containsKey('msg')) {
      print('[SocialStream-WebRTC] Found "msg" wrapper (VDO.Ninja protocol)');
      print('[SocialStream-WebRTC] msg type: ${data['msg'].runtimeType}');
      
      // The actual message content is in the 'msg' field
      var msgContent = data['msg'];
      
      // If msg is a string, try to parse it as JSON
      if (msgContent is String) {
        print('[SocialStream-WebRTC] msg is a string, attempting to parse as JSON');
        print('[SocialStream-WebRTC] msg string content: $msgContent');
        try {
          msgContent = jsonDecode(msgContent);
          print('[SocialStream-WebRTC] Successfully decoded msg string to: $msgContent');
          print('[SocialStream-WebRTC] Decoded type: ${msgContent.runtimeType}');
        } catch (e) {
          print('[SocialStream-WebRTC] Could not decode msg as JSON: $e');
          print('[SocialStream-WebRTC] Treating as plain text message');
          // Might be a plain text message
          final chatMessage = ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            username: 'User',
            message: msgContent.toString(),
            timestamp: DateTime.now(),
            platform: 'datachannel',
          );
          onChatMessage(chatMessage);
          return;
        }
      }
      
      if (msgContent is Map) {
        print('[SocialStream-WebRTC] msg is a Map with keys: ${msgContent.keys.toList()}');
        
        // Check for overlayNinja format inside msg
        if (msgContent.containsKey('overlayNinja') && msgContent['overlayNinja'] is Map) {
          final overlayData = msgContent['overlayNinja'] as Map<String, dynamic>;
          print('[SocialStream-WebRTC] Found overlayNinja in msg: $overlayData');
          
          final chatMessage = ChatMessage.fromSocialStream({'overlayNinja': overlayData});
          print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
          
          // Skip empty messages
          if (chatMessage.message.isEmpty) {
            print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
            return;
          }
          
          onChatMessage(chatMessage);
          
          // Send acknowledgment
          final messageId = _extractMessageId({'overlayNinja': overlayData});
          if (messageId != null) {
            _sendAcknowledgment(uuid, messageId);
          }
          return;
        }
        
        // Direct chat format in msg
        if (msgContent.containsKey('chatmessage') || msgContent.containsKey('chatname')) {
          print('[SocialStream-WebRTC] Direct chat format in msg');
          print('[SocialStream-WebRTC] chatname: ${msgContent['chatname']}');
          print('[SocialStream-WebRTC] chatmessage: ${msgContent['chatmessage']}');
          final chatMessage = ChatMessage.fromSocialStream(msgContent as Map<String, dynamic>);
          print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
          
          // Skip empty messages
          if (chatMessage.message.isEmpty) {
            print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
            return;
          }
          
          onChatMessage(chatMessage);
          
          // Send acknowledgment
          final messageId = _extractMessageId(msgContent as Map<String, dynamic>);
          if (messageId != null) {
            _sendAcknowledgment(uuid, messageId);
          }
          return;
        }
        
        // Check if the entire msgContent might be a chat message
        print('[SocialStream-WebRTC] Checking if entire msgContent is a chat message...');
        if (msgContent.containsKey('type') || msgContent.containsKey('message') || msgContent.containsKey('text')) {
          print('[SocialStream-WebRTC] Attempting to parse msgContent as chat message');
          try {
            final chatMessage = ChatMessage.fromSocialStream(msgContent as Map<String, dynamic>);
            if (chatMessage.message.isNotEmpty) {
              print('[SocialStream-WebRTC] Successfully created chat message from msgContent');
              onChatMessage(chatMessage);
              return;
            }
          } catch (e) {
            print('[SocialStream-WebRTC] Failed to parse msgContent as chat message: $e');
          }
        }
      }
      
      // If msg is neither string nor map, log it
      print('[SocialStream-WebRTC] msg is neither String nor Map, type: ${msgContent.runtimeType}');
    }
    
    // Check for pipe wrapper (Social Stream format)
    if (data.containsKey('pipe') && data['pipe'] is Map) {
      final pipeData = data['pipe'] as Map<String, dynamic>;
      print('[SocialStream-WebRTC] === PIPE MESSAGE (Social Stream Format) ===');
      print('[SocialStream-WebRTC] pipe keys: ${pipeData.keys.toList()}');
      
      if (pipeData.containsKey('overlayNinja') && pipeData['overlayNinja'] is Map) {
        final overlayData = pipeData['overlayNinja'] as Map<String, dynamic>;
        print('[SocialStream-WebRTC] 🎯 CHAT MESSAGE FOUND in pipe.overlayNinja');
        print('[SocialStream-WebRTC] Chat data: $overlayData');
        
        final chatMessage = ChatMessage.fromSocialStream({'overlayNinja': overlayData});
        print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
        
        // Skip empty messages
        if (chatMessage.message.isEmpty) {
          print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
          return;
        }
        
        print('[SocialStream-WebRTC] Platform: ${chatMessage.platform}, ID: ${chatMessage.id}');
        print('[SocialStream-WebRTC] 📣 CALLING onChatMessage callback...');
        onChatMessage(chatMessage);
        print('[SocialStream-WebRTC] ✅ onChatMessage callback completed');
        
        // Send acknowledgment
        final messageId = _extractMessageId({'overlayNinja': overlayData});
        if (messageId != null) {
          _sendAcknowledgment(uuid, messageId);
        }
        return;
      }
    }
    
    // Check for dataReceived wrapper (legacy format)
    if (data.containsKey('dataReceived') && data['dataReceived'] is Map) {
      final dataReceived = data['dataReceived'] as Map<String, dynamic>;
      print('[SocialStream-WebRTC] === DATARECEIVED MESSAGE (Social Stream Format) ===');
      print('[SocialStream-WebRTC] dataReceived keys: ${dataReceived.keys.toList()}');
      
      if (dataReceived.containsKey('overlayNinja') && dataReceived['overlayNinja'] is Map) {
        final overlayData = dataReceived['overlayNinja'] as Map<String, dynamic>;
        print('[SocialStream-WebRTC] overlayNinja data: $overlayData');
        print('[SocialStream-WebRTC] Found overlayNinja in dataReceived: $overlayData');
        
        final chatMessage = ChatMessage.fromSocialStream({'overlayNinja': overlayData});
        print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
        
        // Skip empty messages
        if (chatMessage.message.isEmpty) {
          print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
          return;
        }
        
        onChatMessage(chatMessage);
        
        // Send acknowledgment
        final messageId = _extractMessageId({'overlayNinja': overlayData});
        if (messageId != null) {
          _sendAcknowledgment(uuid, messageId);
        }
        return;
      }
    }
    
    // Check for direct overlayNinja format
    if (data.containsKey('overlayNinja') && data['overlayNinja'] is Map) {
      final overlayData = data['overlayNinja'] as Map<String, dynamic>;
      print('[SocialStream-WebRTC] Found overlayNinja data: $overlayData');
      
      final chatMessage = ChatMessage.fromSocialStream({'overlayNinja': overlayData});
      print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
      
      // Skip empty messages
      if (chatMessage.message.isEmpty) {
        print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
        return;
      }
      
      onChatMessage(chatMessage);
      
      // Send acknowledgment
      final messageId = _extractMessageId({'overlayNinja': overlayData});
      if (messageId != null) {
        _sendAcknowledgment(uuid, messageId);
      }
      return;
    }
    
    // Check for content wrapper
    if (data.containsKey('content') && data['content'] is Map) {
      final content = data['content'] as Map<String, dynamic>;
      print('[SocialStream-WebRTC] Found content wrapper');
      
      if (content.containsKey('chatmessage')) {
        print('[SocialStream-WebRTC] Processing content as chat message');
        final chatMessage = ChatMessage.fromSocialStream(content);
        print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
        
        // Skip empty messages
        if (chatMessage.message.isEmpty) {
          print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
          return;
        }
        
        onChatMessage(chatMessage);
        
        // Send acknowledgment
        final messageId = _extractMessageId(content);
        if (messageId != null) {
          _sendAcknowledgment(uuid, messageId);
        }
        return;
      }
    }
    
    // Direct chat message format
    if (data.containsKey('chatmessage') || data.containsKey('chatname')) {
      print('[SocialStream-WebRTC] Direct chat message format');
      final chatMessage = ChatMessage.fromSocialStream(data);
      print('[SocialStream-WebRTC] Created chat message: "${chatMessage.message}" from "${chatMessage.username}"');
      
      // Skip empty messages
      if (chatMessage.message.isEmpty) {
        print('[SocialStream-WebRTC] Skipping empty message after HTML stripping');
        return;
      }
      
      onChatMessage(chatMessage);
      
      // Send acknowledgment
      final messageId = _extractMessageId(data);
      if (messageId != null) {
        _sendAcknowledgment(uuid, messageId);
      }
      return;
    }
    
    // Handle miniInfo status messages (stats/connection info)
    if (data.containsKey('miniInfo')) {
      print('[SocialStream-WebRTC] Received miniInfo status update');
      // These are periodic status updates from VDO.Ninja, acknowledge them
      final channel = _dataChannels[uuid];
      if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          // Send back a miniInfo response to confirm we're alive
          final response = {
            'miniInfo': {
              'in': {'c': 1}, // Indicate we've received 1 connection
            },
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          channel.send(RTCDataChannelMessage(jsonEncode(response)));
          print('[SocialStream-WebRTC] Sent miniInfo response');
        } catch (e) {
          print('[SocialStream-WebRTC] Error sending miniInfo response: $e');
        }
      }
      return;
    }
    
    print('[SocialStream-WebRTC] Message not recognized as chat format');
    print('[SocialStream-WebRTC] Available keys: ${data.keys.toList()}');
    
    // Check if this might be a ping/heartbeat request
    if (data.containsKey('ping') || data.containsKey('heartbeat')) {
      print('[SocialStream-WebRTC] Received ping/heartbeat, sending pong');
      final channel = _dataChannels[uuid];
      if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          final pongMessage = {
            'pong': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          channel.send(RTCDataChannelMessage(jsonEncode(pongMessage)));
        } catch (e) {
          print('[SocialStream-WebRTC] Error sending pong: $e');
        }
      }
    }
  }
  
  
  // Send initial info message when data channel opens
  void _sendDataChannelInfo(String uuid) {
    final channel = _dataChannels[uuid];
    if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final infoMessage = {
          'info': {
            'label': 'dock',  // Must be 'dock' for Social Stream compatibility
            'version': '1.0.0',
            'platform': 'flutter',
            'flutter': true,
            'type': 'viewer',
            'uuid': _uuid,
          }
        };
        
        print('[SocialStream-WebRTC] Sending initial info message to $uuid');
        channel.send(RTCDataChannelMessage(jsonEncode(infoMessage)));
        
        // Start heartbeat for this channel
        _startHeartbeat(uuid);
      } catch (e) {
        print('[SocialStream-WebRTC] Error sending info message: $e');
      }
    }
  }
  
  // Send a message back to acknowledge receipt
  void _sendAcknowledgment(String uuid, String messageId) {
    final channel = _dataChannels[uuid];
    if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final ackMessage = {
          'ack': messageId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        channel.send(RTCDataChannelMessage(jsonEncode(ackMessage)));
      } catch (e) {
        print('[SocialStream-WebRTC] Error sending acknowledgment: $e');
      }
    }
  }
  
  // Extract message ID from various formats
  String? _extractMessageId(Map<String, dynamic> data) {
    // Check common ID fields
    if (data['mid'] != null) return data['mid'].toString();
    if (data['id'] != null) return data['id'].toString();
    if (data['messageId'] != null) return data['messageId'].toString();
    
    // Check in nested structures
    if (data['overlayNinja'] is Map) {
      final overlay = data['overlayNinja'] as Map<String, dynamic>;
      if (overlay['mid'] != null) return overlay['mid'].toString();
      if (overlay['id'] != null) return overlay['id'].toString();
    }
    
    if (data['msg'] is Map) {
      final msg = data['msg'] as Map<String, dynamic>;
      if (msg['mid'] != null) return msg['mid'].toString();
      if (msg['id'] != null) return msg['id'].toString();
    }
    
    return null;
  }
  
  // Heartbeat mechanism to keep connection alive
  
  void _startHeartbeat(String uuid) {
    // Cancel any existing heartbeat timer for this connection
    _heartbeatTimers[uuid]?.cancel();
    
    // Send heartbeat every 10 seconds
    _heartbeatTimers[uuid] = Timer.periodic(Duration(seconds: 10), (timer) {
      final channel = _dataChannels[uuid];
      if (channel != null && channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          final heartbeatMessage = {
            'heartbeat': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'uuid': _uuid,
          };
          
          channel.send(RTCDataChannelMessage(jsonEncode(heartbeatMessage)));
          print('[SocialStream-WebRTC] Sent heartbeat to $uuid');
        } catch (e) {
          print('[SocialStream-WebRTC] Error sending heartbeat: $e');
          timer.cancel();
        }
      } else {
        print('[SocialStream-WebRTC] Stopping heartbeat - channel closed for $uuid');
        timer.cancel();
      }
    });
  }
  
  // This method is now replaced by _handleSDP
  // Keeping for reference but not used
  
  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    try {
      // VDO.Ninja might use either UUID or streamID
      final uuid = data['UUID'] ?? data['streamID'];
      if (uuid == null) {
        print('[SocialStream-WebRTC] No UUID/streamID in ICE candidate');
        print('[SocialStream-WebRTC] ICE candidate data: ${jsonEncode(data)}');
        return;
      }
      
      print('[SocialStream-WebRTC] Handling ICE candidate from UUID: $uuid');
      print('[SocialStream-WebRTC] Current peer connections: ${_peerConnections.keys.toList()}');
      print('[SocialStream-WebRTC] Publisher browser UUID: $_publisherBrowserUuid');
      
      // If we receive ICE candidates from the browser, it might be identifying itself
      if (data.containsKey('session') && _publisherBrowserUuid == null) {
        // Look for a pattern where the browser might be using a different UUID
        print('[SocialStream-WebRTC] Checking if this might be the browser UUID...');
        
        // If we have a peer connection but the UUID doesn't match, this might be the browser's real UUID
        if (_peerConnections.length == 1 && !_peerConnections.containsKey(uuid)) {
          _publisherBrowserUuid = uuid;
          print('[SocialStream-WebRTC] Detected browser UUID from ICE candidate: $_publisherBrowserUuid');
        }
      }
      
      // Try to find the peer connection - it might be under a different UUID
      String? connectionKey = uuid;
      RTCPeerConnection? pc;
      
      // First, check if we have a direct peer connection
      if (_peerConnections.containsKey(uuid)) {
        pc = _peerConnections[uuid];
        print('[SocialStream-WebRTC] Found direct peer connection for UUID: $uuid');
      } else {
        // Check if this UUID maps to another connection
        if (_peerConnectionMapping.containsKey(uuid)) {
          connectionKey = _peerConnectionMapping[uuid]!;
          pc = _peerConnections[connectionKey];
          print('[SocialStream-WebRTC] Found mapped peer connection: $uuid -> $connectionKey');
        } else {
          // Check all peer connections to see if any match
          for (var entry in _peerConnections.entries) {
            // If we only have one peer connection, use it
            if (_peerConnections.length == 1) {
              connectionKey = entry.key;
              pc = entry.value;
              print('[SocialStream-WebRTC] Using only available peer connection: $connectionKey');
              // Map this UUID to the connection
              _peerConnectionMapping[uuid] = connectionKey;
              break;
            }
          }
        }
      }
      
      if (pc == null) {
        print('[SocialStream-WebRTC] WARNING: No peer connection found for UUID: $uuid');
        print('[SocialStream-WebRTC] This ICE candidate will be ignored');
        return;
      }
      
      final candidate = data['candidate'] ?? data;
      final iceCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      
      // Use the connection key for pending candidates
      if (_pendingIceCandidates.containsKey(connectionKey!)) {
        print('[SocialStream-WebRTC] Queuing ICE candidate - no remote description yet');
        // Store for later
        _pendingIceCandidates[connectionKey] ??= [];
        _pendingIceCandidates[connectionKey]!.add(iceCandidate);
      } else {
        await pc.addCandidate(iceCandidate);
        print('[SocialStream-WebRTC] ICE candidate added for connection: $connectionKey (from UUID: $uuid)');
      }
    } catch (e) {
      print('[SocialStream-WebRTC] Error adding ICE candidate: $e');
    }
  }
  
  void _setupPeerConnectionHandlers(RTCPeerConnection pc, String uuid) {
    // Monitor connection state
    pc.onConnectionState = (RTCPeerConnectionState state) {
      print('[SocialStream-WebRTC] Connection state for $uuid: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('[SocialStream-WebRTC] === PEER CONNECTION ESTABLISHED ===');
        print('[SocialStream-WebRTC] Connected to: $uuid');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        print('[SocialStream-WebRTC] Connection failed/closed for: $uuid');
        // Clean up
        _peerConnections.remove(uuid);
        _dataChannels.remove(uuid);
        _pendingIceCandidates.remove(uuid);
        _peerSessions.remove(uuid);
      }
    };
    
    // Handle ICE candidates (VDO.Ninja official WSS format)
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate != null) {
        final candidateMsg = {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'sdpMid': candidate.sdpMid,
          },
          'UUID': uuid,  // Browser's UUID (it will look in pcs[UUID])
          'type': 'remote',  // remote = from remote peer (us) to browser
        };
        
        // Include session if we have it (official WSS mode)
        if (_peerSessions.containsKey(uuid)) {
          candidateMsg['session'] = _peerSessions[uuid]!;
        }
        
        print('[SocialStream-WebRTC] Sending ICE candidate to: $uuid');
        if (_peerSessions.containsKey(uuid)) {
          print('[SocialStream-WebRTC]   Session: ${_peerSessions[uuid]}');
        }
        _rawWebSocket!.add(jsonEncode(candidateMsg));
      }
    };
    
    // Handle incoming data channels
    pc.onDataChannel = (RTCDataChannel channel) {
      print('[SocialStream-WebRTC] Incoming data channel from $uuid: ${channel.label}');
      _dataChannels[uuid] = channel;
      
      channel.onMessage = (RTCDataChannelMessage message) {
        print('[SocialStream-WebRTC] Incoming channel message from $uuid: ${message.text}');
        try {
          final data = jsonDecode(message.text);
          _handleDataChannelMessage(uuid, data);
        } catch (e) {
          print('[SocialStream-WebRTC] Error parsing incoming channel message: $e');
        }
      };
      
      channel.onDataChannelState = (RTCDataChannelState state) {
        print('[SocialStream-WebRTC] Incoming channel state for $uuid: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          print('[SocialStream-WebRTC] === INCOMING DATA CHANNEL OPENED ===');
          print('[SocialStream-WebRTC] Ready to receive messages on channel: ${channel.label}');
          
          // Send initial info message to confirm data channel is ready
          _sendDataChannelInfo(uuid);
        }
      };
    };
  }
  
  Future<void> _processPendingIceCandidates(String uuid) async {
    if (_pendingIceCandidates.containsKey(uuid)) {
      final candidates = _pendingIceCandidates[uuid]!;
      print('[SocialStream-WebRTC] Processing ${candidates.length} pending ICE candidates for: $uuid');
      
      for (var candidate in candidates) {
        try {
          await _peerConnections[uuid]!.addCandidate(candidate);
          print('[SocialStream-WebRTC] Added pending ICE candidate');
        } catch (e) {
          print('[SocialStream-WebRTC] Error adding pending ICE candidate: $e');
        }
      }
      
      _pendingIceCandidates.remove(uuid);
    }
  }
  
  void _requestToViewPeers(List<dynamic> list) {
    if (list.contains(config.sessionId)) {
      print('[SocialStream-WebRTC] Found target streamID: ${config.sessionId}');
      
      // Request to view the session streamID
      final viewMessage = {
        'request': 'play',
        'streamID': config.sessionId,  // View the session itself
      };
      print('[SocialStream-WebRTC] Requesting to view session: ${config.sessionId}');
      print('[SocialStream-WebRTC] Message: ${jsonEncode(viewMessage)}');
      _rawWebSocket!.add(jsonEncode(viewMessage));
      
    } else if (list.isNotEmpty) {
      // If session ID is not in list, try viewing first available peer
      String? targetPeer;
      for (var peer in list) {
        if (peer is String) {
          targetPeer = peer;
          break;
        } else if (peer is Map && peer['streamID'] != null) {
          targetPeer = peer['streamID'];
          break;
        }
      }
      
      if (targetPeer != null) {
        print('[SocialStream-WebRTC] Session ID not found, viewing first peer: $targetPeer');
        final viewMessage = {
          'request': 'play',
          'streamID': targetPeer,
        };
        print('[SocialStream-WebRTC] Message: ${jsonEncode(viewMessage)}');
        _rawWebSocket!.add(jsonEncode(viewMessage));
      }
    }
  }
  
  // Method to send a test chat message
  void sendTestMessage(String text) {
    if (!_isConnected) {
      print('[SocialStream] Cannot send test message - not connected');
      return;
    }
    
    if (config.mode == ConnectionMode.websocket && _rawWebSocket != null) {
      final testMessage = {
        'action': 'send',
        'to': config.sessionId,
        'msg': {
          'chatname': 'Flutter Debug',
          'chatmessage': text,
          'type': 'debug',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };
      print('[SocialStream] Sending test message: ${jsonEncode(testMessage)}');
      _rawWebSocket!.add(jsonEncode(testMessage));
    } else if (config.mode == ConnectionMode.webrtc) {
      // Send test message through data channels
      print('[SocialStream] Sending test message through data channels');
      for (var entry in _dataChannels.entries) {
        final uuid = entry.key;
        final channel = entry.value;
        if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
          try {
            // Try VDO.Ninja format with msg wrapper
            final testMessage = {
              'msg': {
                'overlayNinja': {
                  'chatname': 'Flutter Test',
                  'chatmessage': text,
                  'type': 'test',
                  'mid': DateTime.now().millisecondsSinceEpoch.toString(),
                }
              }
            };
            
            print('[SocialStream] Sending test message to $uuid: ${jsonEncode(testMessage)}');
            channel.send(RTCDataChannelMessage(jsonEncode(testMessage)));
            
            // Also try direct format
            Timer(Duration(milliseconds: 500), () {
              final directMessage = {
                'chatname': 'Flutter Test Direct',
                'chatmessage': text + ' (direct format)',
                'type': 'test',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              };
              print('[SocialStream] Sending direct format test to $uuid: ${jsonEncode(directMessage)}');
              channel.send(RTCDataChannelMessage(jsonEncode(directMessage)));
            });
            
          } catch (e) {
            print('[SocialStream] Error sending test message to $uuid: $e');
          }
        } else {
          print('[SocialStream] Data channel to $uuid is not open (state: ${channel.state})');
        }
      }
    }
  }
  
  // Debug method to log data channel states
  void logDataChannelStates() {
    print('[SocialStream] === DATA CHANNEL STATES ===');
    print('[SocialStream] Total peer connections: ${_peerConnections.length}');
    print('[SocialStream] Total data channels: ${_dataChannels.length}');
    
    for (var entry in _dataChannels.entries) {
      final uuid = entry.key;
      final channel = entry.value;
      print('[SocialStream] Channel $uuid:');
      print('[SocialStream]   Label: ${channel.label}');
      print('[SocialStream]   State: ${channel.state}');
      print('[SocialStream]   ID: ${channel.id}');
      
      // Check if we have a peer connection for this UUID
      if (_peerConnections.containsKey(uuid)) {
        final pc = _peerConnections[uuid]!;
        print('[SocialStream]   PC State: ${pc.connectionState}');
        print('[SocialStream]   PC ICE State: ${pc.iceConnectionState}');
      }
      
      // Check if we have a session for this UUID
      if (_peerSessions.containsKey(uuid)) {
        print('[SocialStream]   Session: ${_peerSessions[uuid]}');
      }
      
      // Check if we have a mapping for this UUID
      if (_browserUuidToStreamId.containsKey(uuid)) {
        print('[SocialStream]   Maps to: ${_browserUuidToStreamId[uuid]}');
      }
    }
    
    print('[SocialStream] Publisher browser UUID: $_publisherBrowserUuid');
    print('[SocialStream] Our UUID: $_uuid');
    print('[SocialStream] === END DATA CHANNEL STATES ===');
  }
  
  void disconnect() {
    _isConnected = false;
    
    // Cancel reconnection attempts
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    
    // Cancel all close timeouts
    for (var timer in _closeTimeouts.values) {
      timer.cancel();
    }
    _closeTimeouts.clear();
    
    // Cancel all heartbeat timers
    for (var timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();
    
    if (_rawWebSocket != null) {
      _rawWebSocket!.close();
      _rawWebSocket = null;
    }
    
    // Close all data channels
    for (var dc in _dataChannels.values) {
      try {
        dc.close();
      } catch (e) {
        print('[SocialStream] Error closing data channel: $e');
      }
    }
    _dataChannels.clear();
    
    // Close all peer connections
    for (var pc in _peerConnections.values) {
      try {
        pc.close();
      } catch (e) {
        print('[SocialStream] Error closing peer connection: $e');
      }
    }
    _peerConnections.clear();
    _pendingIceCandidates.clear();
    _peerSessions.clear();
    _browserUuidToStreamId.clear();
    _peerConnectionMapping.clear();
    
    // _streamId = null;
    _uuid = null;
    _publisherBrowserUuid = null;
  }
  
  void dispose() {
    _reconnectTimer?.cancel();
    
    for (var timer in _closeTimeouts.values) {
      timer.cancel();
    }
    _closeTimeouts.clear();
    
    for (var timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();
    
    disconnect();
  }
  
  // Reconnection logic (aligned with VDO.Ninja)
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[SocialStream] Max reconnection attempts reached');
      return;
    }
    
    int delay;
    if (_reconnectAttempts == 0) {
      // First attempt is near instant
      delay = _initialReconnectDelay;
    } else if (_reconnectAttempts == 1) {
      // Second attempt waits 2 seconds
      delay = _baseReconnectDelay;
    } else if (_reconnectAttempts == 2) {
      // Third attempt waits 5 seconds
      delay = 5000;
    } else {
      // Subsequent attempts wait 10 seconds max
      delay = _maxReconnectDelay;
    }
    
    _reconnectAttempts++;
    print('[SocialStream] Scheduling reconnect attempt $_reconnectAttempts in ${delay}ms');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () async {
      if (!_isConnected && config.enabled) {
        print('[SocialStream] Executing reconnection attempt $_reconnectAttempts');
        await connect();
      }
    });
  }
  
  void _cancelCloseTimeout(String uuid) {
    _closeTimeouts[uuid]?.cancel();
    _closeTimeouts.remove(uuid);
  }
  
  void _scheduleCloseTimeout(String uuid, int delayMs) {
    _cancelCloseTimeout(uuid);
    _closeTimeouts[uuid] = Timer(Duration(milliseconds: delayMs), () {
      print('[SocialStream] Connection timeout for $uuid - closing');
      _cleanupPeerConnection(uuid);
    });
  }
  
  void _cleanupPeerConnection(String uuid) {
    print('[SocialStream] Cleaning up peer connection for $uuid');
    
    // Cancel any pending timers
    _cancelCloseTimeout(uuid);
    _heartbeatTimers[uuid]?.cancel();
    _heartbeatTimers.remove(uuid);
    
    // Close data channel
    if (_dataChannels.containsKey(uuid)) {
      try {
        _dataChannels[uuid]!.close();
      } catch (e) {
        print('[SocialStream] Error closing data channel: $e');
      }
      _dataChannels.remove(uuid);
    }
    
    // Close peer connection
    if (_peerConnections.containsKey(uuid)) {
      try {
        _peerConnections[uuid]!.close();
      } catch (e) {
        print('[SocialStream] Error closing peer connection: $e');
      }
      _peerConnections.remove(uuid);
    }
    
    // Clean up mappings
    _pendingIceCandidates.remove(uuid);
    _peerSessions.remove(uuid);
    _browserUuidToStreamId.removeWhere((key, value) => key == uuid || value == uuid);
    _peerConnectionMapping.remove(uuid);
    
    // If no more connections and we should be connected, schedule reconnect
    if (_peerConnections.isEmpty && config.enabled && _isConnected) {
      print('[SocialStream] All peer connections lost - scheduling reconnect');
      _scheduleReconnect();
    }
  }
  
  // Handle connection failure with ICE restart (VDO.Ninja style)
  Future<void> _handleConnectionFailure(String uuid) async {
    print('[SocialStream] Connection failed for $uuid - attempting ICE restart');
    
    final pc = _peerConnections[uuid];
    if (pc == null) {
      print('[SocialStream] No peer connection found for $uuid');
      return;
    }
    
    try {
      // VDO.Ninja approach: try ICE restart first
      print('[SocialStream] Attempting ICE restart for $uuid');
      
      // Create offer with iceRestart flag
      final offer = await pc.createOffer({
        'iceRestart': true,
      });
      await pc.setLocalDescription(offer);
      
      // Send updated offer with session preserved
      final offerMsg = {
        'description': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'UUID': uuid,
        'streamID': _uuid,
        'iceRestart': true,
      };
      
      // Preserve session for reconnection
      if (_peerSessions.containsKey(uuid)) {
        offerMsg['session'] = _peerSessions[uuid]!;
      }
      
      print('[SocialStream] Sending ICE restart offer to $uuid');
      _rawWebSocket?.add(jsonEncode(offerMsg));
      
      // Set a timeout for ICE restart
      _scheduleCloseTimeout(uuid, 10000); // 10 second timeout for ICE restart
      
    } catch (e) {
      print('[SocialStream] ICE restart failed: $e');
      _scheduleCloseTimeout(uuid, 5000);
    }
  }
}

class ChatMessage {
  final String id;
  final String username;
  final String message;
  final DateTime timestamp;
  final String? avatarUrl;
  final String platform;
  final Map<String, dynamic>? metadata;
  
  String get author => username; // Alias for compatibility
  String get content => message; // Alias for compatibility
  
  ChatMessage({
    required this.id,
    required this.username,
    required this.message,
    required this.timestamp,
    this.avatarUrl,
    this.platform = 'unknown',
    this.metadata,
  });
  
  factory ChatMessage.fromSocialStream(Map<String, dynamic> data) {
    print('[ChatMessage] === PARSING MESSAGE ===');
    print('[ChatMessage] Raw data: $data');
    print('[ChatMessage] Data keys: ${data.keys.toList()}');
    
    // Check if data is wrapped in overlayNinja as per JavaScript examples
    Map<String, dynamic> messageData = data;
    if (data.containsKey('overlayNinja') && data['overlayNinja'] is Map) {
      print('[ChatMessage] Found overlayNinja wrapper');
      messageData = data['overlayNinja'] as Map<String, dynamic>;
      print('[ChatMessage] overlayNinja keys: ${messageData.keys.toList()}');
    }
    
    // Check if data is wrapped in msg field
    if (data.containsKey('msg') && data['msg'] is Map) {
      print('[ChatMessage] Found msg wrapper');
      messageData = data['msg'] as Map<String, dynamic>;
      print('[ChatMessage] msg keys: ${messageData.keys.toList()}');
    }
    
    // Check if data is wrapped in content field
    if (data.containsKey('content') && data['content'] is Map) {
      print('[ChatMessage] Found content wrapper');
      messageData = data['content'] as Map<String, dynamic>;
      print('[ChatMessage] content keys: ${messageData.keys.toList()}');
    }
    
    // Extract fields based on JavaScript examples and various formats
    final id = messageData['mid'] ?? 
               messageData['id'] ?? 
               messageData['messageId'] ??
               messageData['messageid'] ??
               data['mid'] ?? // Check parent level too
               data['id'] ?? // Check parent level too
               DateTime.now().millisecondsSinceEpoch.toString();
    
    final username = messageData['chatname'] ?? 
                     messageData['author'] ?? 
                     messageData['username'] ??
                     messageData['from'] ??
                     messageData['name'] ??
                     messageData['displayName'] ??
                     messageData['display_name'] ??
                     data['chatname'] ?? // Check parent level
                     data['from'] ?? // Check parent level
                     'Anonymous';
    
    var message = messageData['chatmessage'] ?? 
                  messageData['message'] ?? 
                  messageData['text'] ??
                  messageData['content'] ??
                  messageData['msg'] ??
                  messageData['body'] ??
                  data['chatmessage'] ?? // Check parent level
                  data['message'] ?? // Check parent level
                  data['text'] ??
                  '';
    
    // Strip HTML from message
    message = _stripHtml(message.toString());
    print('[ChatMessage] Message after HTML stripping: $message');
    
    final avatarUrl = messageData['chatimg'] ?? 
                      messageData['avatar'] ?? 
                      messageData['profileImage'] ??
                      messageData['profile_image'] ??
                      messageData['image'] ??
                      messageData['img'] ??
                      data['chatimg'] ?? // Check parent level
                      data['avatar'];
    
    // Try to determine platform from various fields
    String platform = 'unknown';
    if (messageData['type'] != null) {
      platform = messageData['type'].toString();
    } else if (messageData['platform'] != null) {
      platform = messageData['platform'].toString();
    } else if (messageData['source'] != null) {
      platform = messageData['source'].toString();
    } else if (data['type'] != null) {
      platform = data['type'].toString();
    } else if (data['platform'] != null) {
      platform = data['platform'].toString();
    }
    
    // Clean up platform names
    if (platform.contains('youtube')) platform = 'youtube';
    else if (platform.contains('twitch')) platform = 'twitch';
    else if (platform.contains('facebook') || platform.contains('fb')) platform = 'facebook';
    else if (platform.contains('twitter') || platform.contains('x.com')) platform = 'twitter';
    else if (platform.contains('discord')) platform = 'discord';
    else if (platform.contains('instagram') || platform.contains('ig')) platform = 'instagram';
    else if (platform.contains('tiktok')) platform = 'tiktok';
    
    print('[ChatMessage] Extracted values:');
    print('[ChatMessage]   ID: $id');
    print('[ChatMessage]   Username: $username');
    print('[ChatMessage]   Message: $message');
    print('[ChatMessage]   Platform: $platform');
    print('[ChatMessage]   Avatar: ${avatarUrl != null ? "present" : "none"}');
    
    // Check for timestamp in various formats
    DateTime timestamp = DateTime.now();
    if (messageData['timestamp'] != null) {
      try {
        timestamp = DateTime.fromMillisecondsSinceEpoch(messageData['timestamp']);
      } catch (e) {
        print('[ChatMessage] Failed to parse timestamp: ${messageData['timestamp']}');
      }
    } else if (data['timestamp'] != null) {
      try {
        timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
      } catch (e) {
        print('[ChatMessage] Failed to parse timestamp: ${data['timestamp']}');
      }
    }
    
    // If message is empty but there's a donation, use donation as message
    if (message.isEmpty) {
      print('[ChatMessage] Empty message content, checking for donation...');
      
      final donation = messageData['hasDonation'] ?? 
                      messageData['donation'] ??
                      data['hasDonation'] ??
                      data['donation'];
      
      if (donation != null && donation.toString().isNotEmpty) {
        message = '💰 ' + donation.toString();
        print('[ChatMessage] Using donation as message: $message');
      } else {
        print('[ChatMessage] Warning: Empty message and no donation');
        print('[ChatMessage] Full messageData: $messageData');
        print('[ChatMessage] Full data: $data');
        // Skip messages with no content
        print('[ChatMessage] Skipping message with no content');
        return ChatMessage(
          id: 'empty_${DateTime.now().millisecondsSinceEpoch}',
          username: username.toString(),
          message: '',
          timestamp: DateTime.now(),
          platform: platform,
        );
      }
    }
    
    return ChatMessage(
      id: id.toString(),
      username: username.toString(),
      message: message.toString(),
      timestamp: timestamp,
      avatarUrl: avatarUrl?.toString(),
      platform: platform.toString(),
      metadata: data, // Store original data
    );
  }
}

// HTML stripping utility function
String _stripHtml(String htmlString) {
  if (htmlString.isEmpty) return '';
  
  // First, decode HTML entities
  htmlString = htmlString
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  
  // Remove script and style tags completely with their content
  htmlString = htmlString.replaceAllMapped(
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, multiLine: true, dotAll: true),
      (match) => '');
  htmlString = htmlString.replaceAllMapped(
      RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, multiLine: true, dotAll: true),
      (match) => '');
  
  // Replace br tags with newlines
  htmlString = htmlString.replaceAllMapped(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      (match) => '\n');
  
  // Replace p and div tags with newlines
  htmlString = htmlString.replaceAllMapped(
      RegExp(r'</?(p|div)[^>]*>', caseSensitive: false),
      (match) => '\n');
  
  // Remove all other HTML tags
  htmlString = htmlString.replaceAllMapped(
      RegExp(r'<[^>]+>'),
      (match) => '');
  
  // Clean up extra whitespace
  htmlString = htmlString
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();
  
  // Collapse multiple spaces into one
  htmlString = htmlString.replaceAll(RegExp(r'\s+'), ' ');
  
  return htmlString;
}