// call_sample.dart
import 'package:flutter/material.dart';
import 'dart:core';
import 'signaling.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math'; // Import math for Point
import 'dart:async';
import '../../main.dart'; // Import for startForegroundService
import 'package:flutter_background_service/flutter_background_service.dart';
import '../models/obs_state.dart';
import '../widgets/obs_controls.dart';
import '../models/social_stream_config.dart';
import '../services/social_stream_service.dart';
import '../widgets/chat_overlay.dart';

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
  final int customBitrate;
  final String customSalt;
  final bool enableSystemAudio;
  final SocialStreamConfig socialStreamConfig;

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
      required this.mirrored,
      this.customBitrate = 0,
      this.customSalt = 'vdo.ninja',
      this.enableSystemAudio = false,
      required this.socialStreamConfig})
      : super(key: key);

  @override
  _CallSampleState createState() => _CallSampleState();
}

class _CallSampleState extends State<CallSample> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  var _selfId = "";
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer =
      RTCVideoRenderer(); // Keep if needed for remote views
  bool _inCalling = false;
  bool muted = false;
  bool torch = false;
  bool videoMuted = false;
  bool preview = true;
  bool mirrored = true;
  bool _showViewLink = true;
  bool _hasViewers = false;
  bool _showOBSControls = false;
  bool _showChat = false; // Will be set to true if Social Stream is enabled
  
  // Social Stream
  SocialStreamService? _socialStreamService;
  final StreamController<ChatMessage> _chatStreamController = StreamController<ChatMessage>.broadcast();
  
  // Connection quality monitoring
  String _connectionQuality = 'Connecting...';
  Color _qualityColor = Colors.orange;
  Timer? _connectionQualityTimer;
  int _retryCount = 0;
  static const int MAX_RETRIES = 3;
  
  // Loading state
  bool _isLoading = true;
  String _loadingMessage = 'Initializing camera...';

  // --- Pinch to Zoom State ---
  double _currentZoom = 1.0;
  double _baseScaleFactor = 1.0;
  static const double _maxZoom = 10.0; // Define a maximum zoom level
  // --------------------------

  Offset? _focusPoint;
  bool _focusPointVisible = false;
  Timer? _focusPointTimer; // Timer to hide the focus indicator
  
  // iOS platform view controller reference
  RTCVideoPlatformViewController? _iosViewController;
  
  // OBS Control state
  Map<String, OBSState> _peerOBSStates = {};
  Map<String, bool> _peerHasOBSControl = {};

  _CallSampleState();

  @override
  initState() {
    super.initState();
    initRenderers();
    // Apply initial state from widget properties
    preview = widget.preview;
    muted = widget.muted;
    mirrored = widget.mirrored;
    // --- Initialize Zoom ---
    _currentZoom = 1.0; // Start at no zoom
    // -----------------------
    _connect();
    
    // Initialize Social Stream if enabled
    if (widget.socialStreamConfig.enabled) {
      _initializeSocialStream();
    }
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize(); // Keep if needed
  }
  
  void _initializeSocialStream() {
    print('[CallSample] === INITIALIZING SOCIAL STREAM ===');
    print('[CallSample] Config enabled: ${widget.socialStreamConfig.enabled}');
    print('[CallSample] Config mode: ${widget.socialStreamConfig.mode}');
    print('[CallSample] Config sessionId: ${widget.socialStreamConfig.sessionId}');
    
    _socialStreamService = SocialStreamService(
      config: widget.socialStreamConfig,
      onChatMessage: (ChatMessage message) {
        print('[CallSample] Chat message received from Social Stream!');
        print('[CallSample] From: ${message.author}');
        print('[CallSample] Message: ${message.content}');
        _chatStreamController.add(message);
      },
    );
    
    // Set chat to visible by default when Social Stream is enabled
    if (widget.socialStreamConfig.enabled && mounted) {
      setState(() {
        _showChat = true;
      });
      print('[CallSample] Chat overlay set to visible by default');
    }
    
    // Connect to Social Stream
    print('[CallSample] Calling Social Stream connect()...');
    _socialStreamService!.connect().then((_) {
      print('[CallSample] Social Stream connect() completed');
    }).catchError((error) {
      print('[CallSample] Error connecting to Social Stream: $error');
    });
  }
  
  void _toggleChat() {
    if (mounted) {
      setState(() {
        _showChat = !_showChat;
      });
      print("Chat visibility toggled: $_showChat");
    }
  }

  @override
  deactivate() {
    _zoomDebounceTimer?.cancel();
    _focusPointTimer?.cancel();
    _connectionQualityTimer?.cancel();
    _chatStreamController.close();
    _socialStreamService?.dispose();

    try {
      _signaling?.close(); // Add null check
    } catch (e) {
      print("Error closing signaling: $e");
    }
    try {
      _localRenderer.dispose();
    } catch (e) {
      print("Error disposing local renderer: $e");
    }
    try {
      _remoteRenderer.dispose();
    } catch (e) {
      print("Error disposing remote renderer: $e");
    }
    
    // Clear iOS controller reference
    _iosViewController = null;
    
    // Temporarily disabled - TODO: Fix foreground service
    /*
    if (Platform.isAndroid) {
      try {
        print("Stopping foreground service on dispose...");
        final service = FlutterBackgroundService();
        service.invoke("stopService");
      } catch (e) {
        print('Error stopping foreground service on dispose: $e');
      }
    }
    */

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }


	Widget _buildVideoRenderer() {
	  // Choose the renderer based on platform and add performance optimizations
	  // Commented out to reduce log spam: print("Building video renderer. Stream: ${_localRenderer.srcObject?.id ?? 'null'}, Preview: $preview, InCalling: $_inCalling");
	  
	  // If loading or no stream is available yet, show a loading state
	  if (_isLoading || _localRenderer.srcObject == null) {
	    return Container(
	      color: Colors.black,
	      child: Center(
	        child: Column(
	          mainAxisAlignment: MainAxisAlignment.center,
	          children: [
	            CircularProgressIndicator(
	              color: Colors.blue,
	              strokeWidth: 3,
	            ),
	            SizedBox(height: 20),
	            Text(
	              _loadingMessage.isNotEmpty ? _loadingMessage : "Starting camera...", 
	              style: TextStyle(color: Colors.white, fontSize: 16),
	            ),
	            SizedBox(height: 8),
	            Text(
	              "Please grant camera and microphone permissions", 
	              style: TextStyle(color: Colors.white70, fontSize: 12),
	            ),
	          ],
	        ),
	      ),
	    );
	  }
	  
	  if (Platform.isIOS) {
		return RTCVideoPlatFormView(
		  onViewReady: (RTCVideoPlatformViewController controller) {
			// Store the controller reference and apply current stream
			_iosViewController = controller;
			controller.srcObject = _localRenderer.srcObject;
			print("iOS RTCVideoPlatformViewController ready with stream: ${_localRenderer.srcObject?.id ?? 'null'}");
		  },
		  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
		  mirror: _shouldMirror(), // Use helper function for mirroring logic
		);
	  } else {
		return RTCVideoView(
		  _localRenderer,
		  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
		  mirror: _shouldMirror(), // Use helper function for mirroring logic
		  filterQuality: FilterQuality.low, // Use low filter quality for better performance
		);
	  }
	}


  // Helper function to determine if mirroring should be applied
  bool _shouldMirror() {
    // Mirror front camera by default, don't mirror rear camera by default.
    // Allow user toggle (`widget.mirrored` / `mirrored` state) to override.
    bool isRearCamera = widget.deviceID == "rear" ||
        widget.deviceID == "environment" ||
        widget.deviceID.contains("0"); // Common identifiers for rear

    return isRearCamera ? !mirrored : mirrored;
  }

  void _toggleViewLink() {
    if (mounted) {
      setState(() {
        _showViewLink = !_showViewLink;
      });
      print("View link visibility toggled: $_showViewLink");
    }
  }
  
  void _toggleOBSControls() {
    if (mounted) {
      setState(() {
        _showOBSControls = !_showOBSControls;
      });
      print("OBS controls visibility toggled: $_showOBSControls");
      
      if (_showOBSControls && _peerOBSStates.isNotEmpty) {
        final obsState = _peerOBSStates.entries.first.value;
        print("Current OBS state for ${_peerOBSStates.entries.first.key}:");
        print("  Recording: ${obsState.recording}");
        print("  Streaming: ${obsState.streaming}");
        print("  VirtualCam: ${obsState.virtualcam}");
        print("  Visibility: ${obsState.visibility}");
        print("  SourceActive: ${obsState.sourceActive}");
        print("  Control Level: ${obsState.details?.controlLevel}");
        print("  Current Scene: ${obsState.details?.currentSceneName}");
        print("  Scenes: ${obsState.details?.scenes}");
      }
    }
  }
  
  bool _shouldShowOBSControls() {
    if (_peerOBSStates.isEmpty) return false;
    
    // Check if ANY connected peer has control level >= 4
    for (var obsState in _peerOBSStates.values) {
      final controlLevel = obsState.details?.controlLevel ?? 0;
      if (controlLevel >= 4) {
        return true;
      }
    }
    
    return false;
  }
  
  int _getHighestControlLevel() {
    int highestLevel = 0;
    for (var obsState in _peerOBSStates.values) {
      final controlLevel = obsState.details?.controlLevel ?? 0;
      if (controlLevel > highestLevel) {
        highestLevel = controlLevel;
      }
    }
    return highestLevel;
  }
  
  // Get the peer with the highest control level
  MapEntry<String, OBSState>? _getPeerWithHighestControl() {
    MapEntry<String, OBSState>? bestPeer;
    int highestLevel = 0;
    
    for (var entry in _peerOBSStates.entries) {
      final controlLevel = entry.value.details?.controlLevel ?? 0;
      if (controlLevel > highestLevel) {
        highestLevel = controlLevel;
        bestPeer = entry;
      }
    }
    
    return bestPeer;
  }

  void _connect() async {
    if (widget.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    } else {
      // Explicitly allow portrait if not landscape
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation
            .landscapeRight, // Still allow landscape if user rotates
        DeviceOrientation.landscapeLeft,
      ]);
    }

    // --- TURN Server Logic ---
    var defaultTurnList = [
      // Keep default as fallback
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

    // Use List<Map<String, dynamic>> initially to avoid casting errors during parsing
    List<Map<String, dynamic>> parsedTurnList = [];

    // Helper function to process fetched servers
    void processFetchedServers(List<dynamic> fetchedServers) {
      parsedTurnList.clear(); // Clear previous results
      parsedTurnList.add(
          {'url': 'stun:stun.l.google.com:19302'}); // Always add default STUN

      for (var serverData in fetchedServers) {
        if (serverData is Map) {
          final serverMap = Map<String, dynamic>.from(serverData);
          final username = serverMap['username'] as String?;
          final credential = serverMap['credential'] as String?;

          if (serverMap.containsKey('url') && serverMap['url'] is String) {
            // Handle single 'url'
            parsedTurnList.add({
              'url': serverMap['url'] as String,
              if (username != null) 'username': username,
              if (credential != null) 'credential': credential,
            });
          } else if (serverMap.containsKey('urls')) {
            // Handle 'urls' list
            final urlsValue = serverMap['urls'];
            List<String> urls = [];
            if (urlsValue is String) {
              // Handle case where 'urls' is accidentally a single string
              urls.add(urlsValue);
            } else if (urlsValue is List) {
              // Safely convert list elements to strings
              urls = urlsValue.map((u) => u.toString()).toList();
            }

            for (String url in urls) {
              parsedTurnList.add({
                'url': url,
                if (username != null) 'username': username,
                if (credential != null) 'credential': credential,
              });
            }
          }
        }
      }
      print("Processed ${parsedTurnList.length} TURN/STUN server entries.");
    }

    if (widget.TURNSERVER == "" ||
        widget.TURNSERVER == "un;pw;turn:turn.x.co:3478") {
      try {
        final uri = Uri.parse("https://turnservers.vdo.ninja/?flutter=" +
            DateTime.now().microsecondsSinceEpoch.toString());
        final response = await http.get(uri);
        print("Fetching TURN servers from vdo.ninja...");
        if (response.statusCode == 200) {
          var fetchedTurnListDynamic = jsonDecode(response.body)['servers'];
          if (fetchedTurnListDynamic is List) {
            processFetchedServers(fetchedTurnListDynamic); // Use the helper
            print("Using fetched TURN servers from vdo.ninja.");
          } else {
            print("Fetched TURN server data is not a list, using defaults.");
            parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
          }
        } else {
          print(
              "Failed to fetch TURN servers (Status ${response.statusCode}), using defaults.");
          parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
        }
      } on Exception catch (e) {
        print(
            "Error fetching TURN servers ($e), using default hardcoded list.");
        parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
        print("Caught error: $e");
      }
    } else if (widget.TURNSERVER.startsWith("https://") ||
        widget.TURNSERVER.startsWith("http://")) {
      try {
        final uri = Uri.parse(widget.TURNSERVER);
        final response = await http.get(uri);
        print("Fetching TURN servers from custom URL: ${widget.TURNSERVER}");
        if (response.statusCode == 200) {
          var fetchedTurnListDynamic = jsonDecode(response.body)['servers'];
          if (fetchedTurnListDynamic is List) {
            processFetchedServers(fetchedTurnListDynamic); // Use the helper
            print("Using fetched TURN servers from custom URL.");
          } else {
            print(
                "Fetched TURN server data from custom URL is not a list, using defaults.");
            parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
          }
        } else {
          print(
              "Failed to fetch TURN servers from custom URL (Status ${response.statusCode}), using defaults.");
          parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
        }
      } on Exception catch (e) {
        print(
            "Error fetching TURN servers from custom URL ($e), using default hardcoded list.");
        parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
      }
    } else {
      // --- Custom TURN string parsing ---
      print("Parsing custom TURN string: ${widget.TURNSERVER}");
      var customturn = widget.TURNSERVER.split(";");
      // Start with default STUN
      parsedTurnList = [
        {'url': 'stun:stun.l.google.com:19302'}
      ];

      if (customturn.length == 3 && customturn[2].isNotEmpty) {
        // un;pw;uri
        parsedTurnList.add({
          'url': customturn[2],
          'username': customturn[0],
          'credential': customturn[1]
        });
        print("Using custom TURN server (with credentials).");
      } else if (customturn.length == 1 && customturn[0].isNotEmpty) {
        // Just URI or keyword
        String uri = customturn[0];
        if (uri.startsWith("turn:") || uri.startsWith("turns:")) {
          parsedTurnList.add({'url': uri});
          print("Using custom TURN/TURNS server (no credentials).");
        } else if (uri.startsWith("stun:")) {
          // Replace default STUN only if a custom one is explicitly given
          if (parsedTurnList.isNotEmpty &&
              parsedTurnList[0]['url'] == 'stun:stun.l.google.com:19302') {
            parsedTurnList[0] = {'url': uri};
          } else {
            parsedTurnList.insert(
                0, {'url': uri}); // Add at beginning if default was removed
          }
          print("Using custom STUN server: $uri");
        } else if (["false", "0", "off", "none"].contains(uri.toLowerCase())) {
          // Keep only the default STUN added initially
          parsedTurnList.removeWhere(
              (server) => server['url'] != 'stun:stun.l.google.com:19302');
          print("Disabling TURN, using only STUN.");
        } else {
          // Assume it's a TURN URI without prefix if not recognized
          parsedTurnList.add({'url': 'turn:$uri'});
          print(
              "Using custom TURN server (assumed 'turn:' prefix, no credentials).");
        }
      } else {
        print("Invalid custom TURN format, using default TURN list.");
        parsedTurnList = List<Map<String, dynamic>>.from(defaultTurnList);
      }
    }

    // Ensure the final list passed to Signaling is correctly typed List<Map<String, String>>
    List<Map<String, String>> finalTurnListForSignaling = parsedTurnList
        .map((server) =>
            server.map((key, value) => MapEntry(key, value.toString())))
        .toList();

    // Handle empty WebSocket address - revert to default
    String effectiveWSS = widget.WSSADDRESS.trim().isEmpty 
        ? 'wss://wss.vdo.ninja:443' 
        : widget.WSSADDRESS;
    
    print("Final WebSocket address: $effectiveWSS");

    // Initialize Signaling with the processed TURN list
    _signaling = Signaling(
        widget.streamID,
        widget.deviceID,
        widget.audioDeviceId,
        widget.roomID,
        widget.quality,
        effectiveWSS,
        finalTurnListForSignaling,
        widget.password,
        widget.customBitrate,
        widget.customSalt,
        widget.enableSystemAudio,
        widget.socialStreamConfig);

    // Set up callbacks
    _signaling?.onSignalingStateChange = (SignalingState state) {
      print('Signaling state changed: $state');
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Connection Lost: $state"),
              duration: Duration(seconds: 3),
            ));
          }
          break;
        case SignalingState.ConnectionOpen:
          if (mounted) {
            print("Signaling connection open.");
          }
          break;
      }
    };

    _signaling?.onCallStateChange = (CallState state) {
      print('Call state changed: $state');
      switch (state) {
        case CallState.CallStateNew:
          if (mounted) {
            setState(() {
              _inCalling = true;
              _isLoading = false;
              _loadingMessage = '';
            });
            MediaStream? localStream = _signaling?.getLocalStream();
            if (localStream != null) {
              _assignLocalStream(localStream);
              print("Local stream assigned to renderer in CallStateNew.");
            } else {
              print("Error: Local stream is null in CallStateNew.");
            }
          }
          break;
        case CallState.CallStateBye:
          if (mounted) {
            setState(() {
              _inCalling = false;
            });
            _assignLocalStream(null);
            _remoteRenderer.srcObject = null;
          }
          break;
        case CallState.CallStateInvite:
        case CallState.CallStateConnected:
          print("Call connected.");
          break;
        case CallState.CallStateRinging:
          break;
      }
    };

    _signaling?.onPeersUpdate = ((event) {
      if (mounted) {
        // Handle OBS state updates
        if (event['event'] == 'obsStateUpdate') {
          final uuid = event['uuid'] as String;
          final obsState = event['obsState'] as OBSState;
          print("OBS state update received for peer $uuid");
          setState(() {
            _peerOBSStates[uuid] = obsState;
            _peerHasOBSControl[uuid] = _signaling?.hasOBSControl(uuid) ?? false;
            
            // If OBS controls are open but no peer has control anymore, close them
            if (_showOBSControls && !_shouldShowOBSControls()) {
              print("OBS permissions revoked - closing controls");
              _showOBSControls = false;
            }
          });
        } else {
          // Handle regular peer updates
          print("Peer update received: ${event.toString()}");
          setState(() {
            _selfId = event['self'];
            _peers = event['peers'];

            // Clean up OBS states for disconnected peers
            _peerOBSStates.removeWhere((uuid, _) => !_peers.any((peer) => peer['uuid'] == uuid));
            _peerHasOBSControl.removeWhere((uuid, _) => !_peers.any((peer) => peer['uuid'] == uuid));

            // Auto-hide view link when someone connects
            if (_peers.length > 0 && _showViewLink && !_hasViewers) {
              _showViewLink = false;
              _hasViewers = true;
              print("Auto-hiding view link due to viewer connection");
            }
          });
          
          // Debug: Check stream status after peer update
          print("After peer update - Preview: $preview, InCalling: $_inCalling, Stream: ${_localRenderer.srcObject?.id ?? 'null'}");
          print("Current OBS states for peers: ${_peerOBSStates.keys.toList()}");
        }
      }
    });

    _signaling?.onLocalStream = ((stream) {
      print("Local stream received in onLocalStream callback.");
      if (mounted) {
        _assignLocalStream(stream);
      }
    });

    _signaling?.onAddRemoteStream = ((stream) {
      print("Remote stream added.");
      if (mounted) {
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
    });

    _signaling?.onRemoveRemoteStream = ((stream) {
      print("Remote stream removed.");
      if (mounted) {
        _remoteRenderer.srcObject = null;
        setState(() {});
      }
    });

    _signaling?.onDataChannelMessage = (RTCDataChannel dc, RTCDataChannelMessage message) {
      print("Data channel message received on channel ${dc.label}: ${message.text}");
    };

    _signaling?.onDataChannel = (RTCDataChannel dc) {
      print("Data channel created: ${dc.label}");
    };

    // Temporarily disable foreground service to prevent crashes
    // TODO: Implement a more robust background service solution
    /*
    if (Platform.isAndroid) {
      try {
        print("Starting foreground service for WebRTC streaming...");
        bool serviceStarted = await startForegroundService();
        if (!serviceStarted) {
          print('Warning: Failed to start foreground service');
        } else {
          print('Foreground service started successfully');
        }
      } catch (e) {
        print('Error starting foreground service: $e');
        // Continue anyway - the app might work without it
      }
    }
    */
    
    // Connect with retry logic
    await _connectWithRetry();
    print("Signaling connect called.");
    
    // Start monitoring connection quality
    _startConnectionQualityMonitoring();
  }
  
  Future<void> _connectWithRetry() async {
    try {
      await _signaling?.connect();
      _retryCount = 0;
      _updateConnectionQuality('Connected', Colors.green);
    } catch (e) {
      print("Connection failed: $e");
      if (_retryCount < MAX_RETRIES) {
        _retryCount++;
        _updateConnectionQuality('Retrying... (${_retryCount}/$MAX_RETRIES)', Colors.orange);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed. Retrying... (Attempt ${_retryCount}/$MAX_RETRIES)'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        await Future.delayed(Duration(seconds: 2 * _retryCount));
        return _connectWithRetry();
      } else {
        _updateConnectionQuality('Failed', Colors.red);
        if (mounted) {
          _showConnectionErrorDialog();
        }
      }
    }
  }
  
  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Connection Failed'),
          content: Text('Unable to establish connection after $MAX_RETRIES attempts.\n\nPlease check your internet connection and try again.'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                _hangUp();
              },
            ),
            TextButton(
              child: Text('Retry'),
              onPressed: () {
                Navigator.of(context).pop();
                _retryCount = 0;
                _connectWithRetry();
              },
            ),
          ],
        );
      },
    );
  }
  
  void _updateConnectionQuality(String quality, Color color) {
    if (mounted) {
      setState(() {
        _connectionQuality = quality;
        _qualityColor = color;
      });
    }
  }
  
  void _startConnectionQualityMonitoring() {
    _connectionQualityTimer = Timer.periodic(Duration(seconds: 2), (_) {
      if (_signaling?.active == true) {
        // In a real implementation, you would check actual connection stats
        _updateConnectionQuality('Connected', Colors.green);
      }
    });
  }

  _hangUp() {
    if (mounted) {
      print("Hanging up...");
      _signaling?.close(); // Add null check
      _inCalling = false;
      _currentZoom = 1.0;
      
      // Temporarily disabled - TODO: Fix foreground service
      /*
      if (Platform.isAndroid) {
        try {
          print("Stopping foreground service...");
          final service = FlutterBackgroundService();
          service.invoke("stopService");
        } catch (e) {
          print('Error stopping foreground service: $e');
        }
      }
      */

      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else {
        print("Cannot pop context.");
      }
    }
  }

  _switchCamera() {
    if (_signaling?.active == true) {
      // Add null check
      print("Switching camera...");
      _signaling?.switchCamera(); // Add null check
      setState(() {
        _currentZoom = 1.0;
        _applyZoom(_currentZoom);
      });
    }
  }

  double _lastAppliedZoom = 1.0;
  Timer? _zoomDebounceTimer;
  DateTime _lastZoomTime = DateTime.now();

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScaleFactor = _currentZoom;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_signaling?.active != true ||
        widget.deviceID == 'screen' ||
        widget.deviceID == 'microphone') return;

    double newZoom = _baseScaleFactor * details.scale;
    newZoom = newZoom.clamp(1.0, _maxZoom);

    if (mounted) {
      setState(() {
        _currentZoom = newZoom;
      });
    }

    if ((_lastAppliedZoom - newZoom).abs() > 0.1) {
      _lastAppliedZoom = newZoom;

      _zoomDebounceTimer?.cancel();

      final capturedZoom = newZoom;

      _zoomDebounceTimer = Timer(Duration(milliseconds: 100), () {
        try {
          if (_signaling?.active == true) {
            // Add null check
            _signaling?.zoomCamera(capturedZoom); // Add null check
          }
        } catch (e) {
          print("Error applying zoom: $e");
        }
      });
    }
  }

  void _applyZoom(double zoomLevel) {
    if (mounted && _signaling?.active == true) {
      // Add null check
      _signaling?.zoomCamera(zoomLevel); // Add null check
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (_signaling?.active != true ||
        widget.deviceID == "screen" ||
        widget.deviceID == "microphone") return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final Offset localPosition = box.globalToLocal(details.globalPosition);

    if (localPosition.dx < 0 ||
        localPosition.dx > box.size.width ||
        localPosition.dy < 0 ||
        localPosition.dy > box.size.height) {
      print("Tap outside video bounds.");
      return;
    }

    final double x = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
    final double y = (localPosition.dy / box.size.height).clamp(0.0, 1.0);

    final Point<double> normalizedPoint = Point<double>(x, y);

    try {
      _signaling?.setFocusPoint(normalizedPoint); // Add null check
      _signaling?.setExposurePoint(normalizedPoint); // Add null check
      print("Focus/Exposure point set.");
    } catch (e) {
      print("Error setting focus/exposure point: $e");
    }

    _showFocusIndicator(localPosition);
  }

  void _showFocusIndicator(Offset position) {
    _focusPointTimer?.cancel(); // Cancel previous timer if any
    if (mounted) {
      setState(() {
        _focusPoint = position;
        _focusPointVisible = true;
      });
    }

    // Hide the focus point indicator after a short duration
    _focusPointTimer = Timer(Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _focusPointVisible = false;
        });
      }
    });
  }

  void _assignLocalStream(MediaStream? stream) {
    if (!mounted) return;
    
    print("Assigning local stream: ${stream?.id ?? 'null'} to renderer");
    setState(() {
      _localRenderer.srcObject = stream;
      
      // For iOS, also update the platform view controller if it exists
      if (Platform.isIOS && _iosViewController != null) {
        _iosViewController!.srcObject = stream;
        print("Updated iOS platform view controller with stream: ${stream?.id ?? 'null'}");
      }
      
      if (stream != null) {
        _applyZoom(_currentZoom);
      }
    });
  }
  // ------------------------------------

  _toggleFlashlight() async {
    if (_signaling?.active == true) {
      // Add null check
      bool newTorchState = !torch;
      print("Toggling torch to: $newTorchState");
      bool success = await _signaling!
          .toggleTorch(newTorchState); // Use ! here since we checked active
      if (mounted) {
        setState(() {
          torch = success ? newTorchState : false;
        });
        if (!success) {
          print("Torch toggle failed or not supported.");
        }
      }
    }
  }

  void _toggleMirror() {
    if (_signaling?.active == true) {
      // Add null check
      setState(() {
        mirrored = !mirrored;
      });
      print("Video mirroring toggled: $mirrored");
    }
  }

  _toggleMic() {
    if (_signaling?.active == true) {
      // Add null check
      setState(() {
        muted = !muted;
      });
      _signaling?.muteMic(); // Add null check
      print("Mic muted: $muted");
    }
  }

  void _toggleVideoMute() {
    if (_signaling?.active == true) {
      // Add null check
      setState(() {
        videoMuted = !videoMuted;
      });
      _signaling?.toggleVideoMute(); // Add null check
      print("Video muted: $videoMuted");
    }
  }

  _togglePreview() {
    if (_signaling?.active != true) return;

    bool newPreviewState = !preview;
    print("Toggling preview to: $newPreviewState");

    MediaStream? stream = _signaling?.getLocalStream(); // Add null check

    if (newPreviewState) {
      if (stream != null) {
        _assignLocalStream(stream);
      } else {
        print("Error: Cannot enable preview, local stream is null.");
        return;
      }
    } else {
      _assignLocalStream(null);
    }

    if (mounted) {
      setState(() {
        preview = newPreviewState;
      });
    }
  }

  IconData _getQualityIcon() {
    switch (_connectionQuality) {
      case 'Connected':
        return Icons.signal_cellular_alt;
      case 'Failed':
        return Icons.signal_cellular_off;
      case 'Connecting...':
        return Icons.signal_cellular_connected_no_internet_4_bar;
      default:
        return Icons.sync;
    }
  }

  _info() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Prepare the view link with proper hashing
            String vdonLink = "https://vdo.ninja/?view=${widget.streamID}";
    
			if ((widget.password == "0") || (widget.password == "false") || (widget.password == "off") || (widget.password == "")) {
			  vdonLink += "&p=0";
			} else if (widget.password != "someEncryptionKey123" && widget.password.isNotEmpty) {
			  // Add password hash when a custom password is provided
			  if (_signaling?.hashcode?.isNotEmpty == true) {
				vdonLink += _signaling!.hashcode;
			  }
			}
			
			if (widget.roomID.isNotEmpty) {
			  vdonLink += "&room=${widget.roomID}";
			  
			}
			
			if (widget.WSSADDRESS != 'wss://wss.vdo.ninja:443') {
			  vdonLink += "&wss=" + Uri.encodeComponent(widget.WSSADDRESS.replaceAll("wss://", ""));
			}

        return AlertDialog(
          title: Text("Info & Tips"),
          content: SingleChildScrollView(
            child: Text(
              "• View Link: $vdonLink\n\n"
			  "• Share the link above to allow viewing.\n\n" +
			  "• Quality Tips:\n" +
			  "  - Add '&bitrate=6000' or '&codec=vp9' (or h264/av1) to the view link for potential quality changes.\n" +
			  "  - Ensure a stable network connection.\n" +
			  "  - Check https://docs.vdo.ninja for more parameters.",
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Copy Link'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: vdonLink));
                Navigator.of(context).pop(); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Link copied to clipboard!')),
                );
              },
            ),
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var buttonWidth = 51.0;
    var buttonPadding = 15.0;

    if (widget.deviceID == 'microphone') {
      buttonWidth = 60.0;
      buttonPadding = 15.0;
    }

    String vdonLink = "https://vdo.ninja/?view=${widget.streamID}";
    
	if ((widget.password == "0") || (widget.password == "false") || (widget.password == "off") || (widget.password == "")) {
	  vdonLink += "&p=0";
	} else if (widget.password != "someEncryptionKey123" && widget.password.isNotEmpty) {
	  // Add password hash when a custom password is provided
	  if (_signaling?.hashcode?.isNotEmpty == true) {
		vdonLink += _signaling!.hashcode;
	  }
	}
	
	if (widget.roomID.isNotEmpty) {
	  vdonLink += "&room=${widget.roomID}";
	  
	}
	
	if (widget.WSSADDRESS != 'wss://wss.vdo.ninja:443') {
	  vdonLink += "&wss=" + Uri.encodeComponent(widget.WSSADDRESS.replaceAll("wss://", ""));
	}

    List<Widget> buttons = [];

    // --- Build Buttons (Mostly existing logic, minor adjustments) ---
    buttons.add(
      RawMaterialButton(
        constraints: BoxConstraints(minWidth: buttonWidth),
        visualDensity: VisualDensity.comfortable,
        onPressed: _toggleMic, // Use direct function reference
        fillColor: muted ? Colors.red : Colors.green,
        child: Icon(muted ? Icons.mic_off : Icons.mic, color: Colors.white),
        shape: CircleBorder(),
        elevation: 2,
        padding: EdgeInsets.all(buttonPadding),
      ),
    );

    if (widget.deviceID != 'microphone') {
      // Show video controls unless mic-only
      if (widget.deviceID != 'screen') {
        // Screen share doesn't have preview toggle
        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: _togglePreview,
          fillColor: preview ? Colors.green : Colors.red,
          child: Icon(preview ? Icons.visibility : Icons.visibility_off,
              color: Colors.white), // Changed icons
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(buttonPadding),
        ));
      }

      buttons.add(RawMaterialButton(
        constraints: BoxConstraints(minWidth: buttonWidth),
        visualDensity: VisualDensity.comfortable,
        onPressed: _toggleVideoMute,
        fillColor: videoMuted ? Colors.red : Colors.green,
        child: Icon(videoMuted ? Icons.videocam_off : Icons.videocam,
            color: Colors.white),
        shape: CircleBorder(),
        elevation: 2,
        padding: EdgeInsets.all(buttonPadding),
      ));

      if (widget.deviceID != 'screen') {
        // Screen share doesn't have camera switch/mirror/flash
        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: _switchCamera,
          fillColor: Colors.blue, // Use a different color for non-state buttons
          child: Icon(Icons.cameraswitch, color: Colors.white),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(buttonPadding),
        ));

        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: _toggleMirror,
          fillColor: Colors.blue,
          // Use AutoAwesomeMotion for mirror icon or keep compare_arrows
          child: Icon(
              mirrored ? Icons.flip_camera_ios : Icons.flip_camera_ios_outlined,
              color: Colors.white), // Example icons
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(buttonPadding),
        ));

        buttons.add(RawMaterialButton(
          constraints: BoxConstraints(minWidth: buttonWidth),
          visualDensity: VisualDensity.comfortable,
          onPressed: _toggleFlashlight,
          fillColor:
              torch ? Colors.yellow : Colors.blueGrey, // More indicative colors
          child: Icon(!torch ? Icons.flashlight_off : Icons.flashlight_on,
              color: torch ? Colors.black : Colors.white),
          shape: CircleBorder(),
          elevation: 2,
          padding: EdgeInsets.all(buttonPadding),
        ));
      }
    }

    buttons.add(RawMaterialButton(
      constraints: BoxConstraints(minWidth: buttonWidth),
      visualDensity: VisualDensity.comfortable,
      onPressed: _hangUp,
      fillColor: Colors.redAccent, // Slightly different red
      child: Icon(Icons.call_end, color: Colors.white),
      shape: CircleBorder(),
      elevation: 2,
      padding: EdgeInsets.all(buttonPadding),
    ));
    // ----------------------------------------------------

    Widget controlsWidget = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(
            10.0), // Outer padding for the whole bar from screen edges
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: GestureDetector(
            // Keep this for the dead zone
            onTap: () {
              // Absorbs taps on the background area.
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              // The background container
              color: Colors.black.withOpacity(0.5),
              // Add padding *inside* the container, around the Wrap
              // Adjust horizontal padding for edge spacing, vertical for top/bottom space
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
              child: Wrap(
                // Wrap directly inside the padded container
                alignment: WrapAlignment
                    .center, // Center buttons horizontally on each line
                spacing:
                    2.0, // Horizontal space BETWEEN buttons (adjust as needed)
                runSpacing:
                    4.0, // Vertical space between rows if wrapping occurs
                children: buttons, // Your list of button widgets
              ),
            ),
          ),
        ),
      ),
    );

    // Main return statement for build method
    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKey: _handleKeyEvent,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight), // Standard height
        child: SafeArea(
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
                    icon: Icon(Icons.arrow_back_ios),
                    color: Colors.white,
                    tooltip: "Back",
                    onPressed: () => _hangUp(),
                  ),
                  SizedBox(width: 2),
                  // Only show info button when view link is shown
                  if (_showViewLink)
                    IconButton(
                      icon: Icon(Icons.info_outline),
                      color: Colors.white,
                      tooltip: "Info & Share Link",
                      onPressed: _info,
                    ),
                ],
              ),
            ),
            actions: [
              // Chat Button - show when Social Stream is enabled
              if (widget.socialStreamConfig.enabled && _socialStreamService != null) ...[
                IconButton(
                  icon: Icon(_showChat ? Icons.chat_bubble : Icons.chat_bubble_outline),
                  color: _showChat ? Colors.purple : Colors.white,
                  tooltip: _showChat ? "Hide Chat" : "Show Chat",
                  onPressed: _toggleChat,
                ),
                // Connection status indicator
                IconButton(
                  icon: Icon(
                    _socialStreamService?.isConnected == true 
                      ? Icons.cloud_done 
                      : Icons.cloud_off
                  ),
                  color: _socialStreamService?.isConnected == true 
                    ? Colors.green 
                    : Colors.red,
                  tooltip: _socialStreamService?.isConnected == true 
                    ? "Social Stream Connected" 
                    : "Social Stream Disconnected",
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _socialStreamService?.isConnected == true 
                            ? 'Social Stream connected to session: ${widget.socialStreamConfig.sessionId}'
                            : 'Social Stream not connected'
                        ),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                ),
                // Debug button to send test message
                IconButton(
                  icon: Icon(Icons.bug_report),
                  color: Colors.orange,
                  tooltip: "Send Test Message",
                  onPressed: () {
                    print("Sending test message via Social Stream");
                    _socialStreamService?.sendTestMessage("Test message at ${DateTime.now().toIso8601String()}");
                  },
                ),
              ],
              // OBS Control Button - show when we have OBS state
              if (_peerOBSStates.isNotEmpty && _shouldShowOBSControls())
                IconButton(
                  icon: Icon(Icons.gamepad),
                  color: Colors.purple,
                  tooltip: "OBS Controls",
                  onPressed: _toggleOBSControls,
                ),
              // Only show share button when view link is shown
              if (_showViewLink)
                IconButton(
                  icon: Icon(Icons.share),
                  color: Colors.white,
                  tooltip: "Share Link",
                  onPressed: () {
                    Share.share("View my stream: $vdonLink");
                  },
                ),
              IconButton(
                icon: Icon(
                    _showViewLink ? Icons.visibility_off : Icons.visibility),
                color: Colors.white,
                tooltip: _showViewLink ? "Hide View Link" : "Show View Link",
                onPressed: _toggleViewLink,
              ),

              SizedBox(
                width: 10,
              )
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Camera view with gesture detection
          GestureDetector(
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            onTapDown: _handleTapDown,
            child: Container(
          color: Colors.black,
          child: Center(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // --- Video Display Area ---
                if (widget.deviceID != 'microphone')
                  Positioned.fill(
                    child: preview && _inCalling
                        ? _buildVideoRenderer()
                        : Container(
                            color: Colors.black,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!preview)
                                    Icon(Icons.visibility_off, color: Colors.white, size: 50),
                                  if (!_inCalling)
                                    CircularProgressIndicator(color: Colors.blue),
                                  SizedBox(height: 10),
                                  Text(
                                    !preview ? "Preview Disabled" : "Connecting...",
                                    style: TextStyle(color: Colors.white, fontSize: 16)
                                  ),
                                ],
                              ),
                            ),
                          ),
                  )
                else // Mic-only specific UI
                  Container(
                    color: Theme.of(context).canvasColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, size: 100, color: Colors.white70),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              "Audio Only Mode\nOpen the view link in a browser.",
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.white, fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // --- Screen Share Specific UI ---
                if (widget.deviceID == 'screen')
                  Positioned(
                    bottom: 100, // Position above the controls
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.screen_share, color: Colors.blue, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Screen Sharing Active",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // --- Focus Indicator ---
                if (_focusPointVisible && _focusPoint != null)
                  Positioned(
                    left: _focusPoint!.dx - 20, // Center the indicator
                    top: _focusPoint!.dy - 20,
                    child: IgnorePointer(
                      // Prevent indicator from intercepting taps
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Colors.yellowAccent, width: 2),
                          shape: BoxShape.circle, // Use circle shape
                        ),
                      ),
                    ),
                  ),

                // Connection Quality Indicator (only show when not connected)
                if (_connectionQuality != 'Connected')
                  Positioned(
                    top: 100,
                    right: 20,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _qualityColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: _qualityColor, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getQualityIcon(),
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _connectionQuality,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // OBS Status Bar - always at top
                if (_peerOBSStates.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {}, // Consume tap events
                      child: OBSStatusBar(
                        obsStates: _peerOBSStates,
                      ),
                    ),
                  ),

                Positioned(
                  top: 48,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _showViewLink ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 200),
                    child: Container(
                      padding: EdgeInsets.only(
                          top: 50, bottom: 10, left: 20, right: 20),
                      color: Colors.black.withAlpha(100),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center, // Center the text
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => {Share.share(vdonLink)},
                              child: Text(
                                "View Link: $vdonLink",
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // --- Controls ---
                Positioned(
                  bottom: 10,
                  left:
                      0, // Let the Padding inside SafeArea handle edge spacing
                  right: 0,
                  child: controlsWidget, // Use the revised widget
                ),
                // ---------------
              ],
            ),
          ),
        ),
      ),
          
          // Chat Overlay
          if (widget.socialStreamConfig.enabled && _showChat)
            ChatOverlay(
              isVisible: _showChat,
              chatStream: _chatStreamController.stream,
            ),
          
          // OBS Controls Panel - moved outside the camera gesture detector
          if (_peerOBSStates.isNotEmpty && _showOBSControls) ...[
            // Semi-transparent backdrop
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleOBSControls, // Close when tapping outside
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
            ),
            // OBS Controls Panel
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
              right: 20,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Absorb tap events to prevent them from reaching the camera view
                },
                onTapDown: (_) {
                  // Absorb tap down events as well
                },
                onScaleStart: (_) {
                  // Absorb scale events
                },
                onScaleUpdate: (_) {
                  // Absorb scale events
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.transparent,
                  child: Container(
                    width: 280,
                    constraints: BoxConstraints(maxHeight: 400),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple, width: 2),
                    ),
                    child: Builder(
                      builder: (context) {
                        final bestPeer = _getPeerWithHighestControl();
                        if (bestPeer == null) {
                          return Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                "No OBS control available",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        }
                        
                        return OBSControlsExpandedPanel(
                          obsState: bestPeer.value,
                          peerUuid: bestPeer.key,
                          controlLevel: bestPeer.value.details?.controlLevel ?? 0,
                          onCommand: (action, {value}) {
                            print("OBS Command triggered in CallSample: $action${value != null ? ' with value: $value' : ''}");
                            if (_signaling != null) {
                              _signaling!.sendOBSCommand(bestPeer.key, action, value: value);
                            } else {
                              print("ERROR: Signaling is null, cannot send OBS command");
                            }
                          },
                          onClose: _toggleOBSControls,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      backgroundColor: Colors.black, // Fallback background
    ));  // Close RawKeyboardListener
  }
  
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyD && 
          event.isControlPressed) {
        // Ctrl+D - Log data channel states
        print('[CallSample] === DEBUG: Logging data channel states ===');
        _socialStreamService?.logDataChannelStates();
      } else if (event.logicalKey == LogicalKeyboardKey.keyT && 
                 event.isControlPressed) {
        // Ctrl+T - Send test message
        print('[CallSample] === DEBUG: Sending test message ===');
        _socialStreamService?.sendTestMessage('Debug test message from keyboard shortcut');
      } else if (event.logicalKey == LogicalKeyboardKey.keyS && 
                 event.isControlPressed) {
        // Ctrl+S - Show Social Stream status
        print('[CallSample] === DEBUG: Social Stream Status ===');
        print('[CallSample] Enabled: ${widget.socialStreamConfig.enabled}');
        print('[CallSample] Mode: ${widget.socialStreamConfig.mode}');
        print('[CallSample] Session: ${widget.socialStreamConfig.sessionId}');
        print('[CallSample] Connected: ${_socialStreamService?.isConnected}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Social Stream Debug:\n'
              'Connected: ${_socialStreamService?.isConnected}\n'
              'Mode: ${widget.socialStreamConfig.mode}\n'
              'Session: ${widget.socialStreamConfig.sessionId}'
            ),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.purple,
          ),
        );
      }
    }
  }
}
