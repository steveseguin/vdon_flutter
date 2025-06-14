# Social Stream WebRTC Reconnection Improvements

Based on analysis of VDO.Ninja source code, here are the key improvements needed for Social Stream WebRTC reconnection logic:

## 1. WebSocket Reconnection with Exponential Backoff

**VDO.Ninja behavior:**
- Automatically reconnects after 5 seconds on disconnect
- Uses exponential backoff for repeated failures
- Maintains session state across reconnections

**Implementation needed:**
```dart
Timer? _reconnectTimer;
int _reconnectAttempts = 0;
final int _maxReconnectAttempts = 10;
final int _baseReconnectDelay = 5000; // 5 seconds

void _scheduleReconnect() {
  if (_reconnectAttempts >= _maxReconnectAttempts) {
    print('[SocialStream] Max reconnection attempts reached');
    return;
  }
  
  // Exponential backoff: 5s, 10s, 20s, 40s... up to 30s max
  final delay = min(_baseReconnectDelay * pow(2, _reconnectAttempts), 30000);
  _reconnectAttempts++;
  
  print('[SocialStream] Scheduling reconnect attempt $_reconnectAttempts in ${delay}ms');
  
  _reconnectTimer?.cancel();
  _reconnectTimer = Timer(Duration(milliseconds: delay), () async {
    if (!_isConnected) {
      await connect();
    }
  });
}
```

## 2. Connection State Monitoring with Platform-Specific Timeouts

**VDO.Ninja behavior:**
- Windows: 10 second timeout for disconnected state
- Other platforms: 5 second timeout
- Automatic cleanup of stale connections

**Implementation needed:**
```dart
Map<String, Timer> _closeTimeouts = {};

void _setupPeerConnectionHandlers(RTCPeerConnection pc, String uuid) {
  pc.onConnectionState = (RTCPeerConnectionState state) {
    print('[SocialStream-WebRTC] Connection state for $uuid: $state');
    
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _cancelCloseTimeout(uuid);
        _reconnectAttempts = 0; // Reset on successful connection
        break;
        
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Platform-specific timeout
        final timeout = Platform.isWindows ? 10000 : 5000;
        _scheduleCloseTimeout(uuid, timeout);
        break;
        
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _handleConnectionFailure(uuid);
        break;
        
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _cleanupPeerConnection(uuid);
        break;
    }
  };
}

void _scheduleCloseTimeout(String uuid, int delayMs) {
  _cancelCloseTimeout(uuid);
  _closeTimeouts[uuid] = Timer(Duration(milliseconds: delayMs), () {
    print('[SocialStream] Connection timeout for $uuid - closing');
    _cleanupPeerConnection(uuid);
  });
}

void _cancelCloseTimeout(String uuid) {
  _closeTimeouts[uuid]?.cancel();
  _closeTimeouts.remove(uuid);
}
```

## 3. ICE Restart Mechanism

**VDO.Ninja behavior:**
- Attempts ICE restart on connection failure
- Falls back to creating new offer with iceRestart flag
- Preserves session during restart

**Implementation needed:**
```dart
Future<void> _handleConnectionFailure(String uuid) async {
  print('[SocialStream] Connection failed for $uuid - attempting ICE restart');
  
  final pc = _peerConnections[uuid];
  if (pc == null) return;
  
  try {
    // Try ICE restart if supported
    if (pc.restartIce != null) {
      await pc.restartIce!();
    } else {
      // Fallback: recreate offer with iceRestart flag
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
      
      if (_peerSessions.containsKey(uuid)) {
        offerMsg['session'] = _peerSessions[uuid]!;
      }
      
      _rawWebSocket?.add(jsonEncode(offerMsg));
    }
  } catch (e) {
    print('[SocialStream] ICE restart failed: $e');
    _scheduleCloseTimeout(uuid, 5000);
  }
}
```

## 4. Network Change Detection

**VDO.Ninja behavior:**
- Monitors online/offline events
- Triggers reconnection on network restoration
- Marks connections as stale on network loss

**Implementation needed:**
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

StreamSubscription<ConnectivityResult>? _connectivitySubscription;

void _initNetworkMonitoring() {
  _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none && !_isConnected) {
      print('[SocialStream] Network restored - attempting reconnection');
      _scheduleReconnect();
    } else if (result == ConnectivityResult.none) {
      print('[SocialStream] Network lost');
      // Mark all connections as potentially stale
      for (var uuid in _peerConnections.keys) {
        _scheduleCloseTimeout(uuid, 5000);
      }
    }
  });
}
```

## 5. Enhanced Heartbeat for Safari/iOS

**VDO.Ninja behavior:**
- Sends heartbeats through data channels on Safari/iOS
- Detects dead connections that appear alive
- Triggers reconnection on heartbeat failure

**Implementation needed:**
```dart
void _startHeartbeat(String uuid) {
  // Only for Apple platforms (Safari has issues with connection state)
  if (!Platform.isIOS && !Platform.isMacOS) return;
  
  _heartbeatTimers[uuid]?.cancel();
  
  int missedHeartbeats = 0;
  _heartbeatTimers[uuid] = Timer.periodic(Duration(seconds: 5), (timer) {
    final channel = _dataChannels[uuid];
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      timer.cancel();
      return;
    }
    
    try {
      channel.send(RTCDataChannelMessage(jsonEncode({
        'heartbeat': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'safari': true,
      })));
      missedHeartbeats = 0;
    } catch (e) {
      missedHeartbeats++;
      if (missedHeartbeats >= 3) {
        print('[SocialStream] Heartbeat failed 3 times - connection likely dead');
        timer.cancel();
        _handleConnectionFailure(uuid);
      }
    }
  });
}
```

## 6. Session Persistence

**VDO.Ninja behavior:**
- Maintains UUID across reconnections
- Preserves peer session mappings
- Tracks connection history

**Implementation needed:**
```dart
// Preserve these across reconnections
String? _persistentUuid;
Map<String, String> _persistentSessions = {};

Future<void> connect() async {
  // Reuse UUID if reconnecting
  if (_persistentUuid != null && _reconnectAttempts > 0) {
    _uuid = _persistentUuid;
    print('[SocialStream] Reusing UUID for reconnection: $_uuid');
  }
  
  // ... rest of connect logic
}

// Store UUID for reconnections
void _onSeedConfirmed(String uuid) {
  _uuid = uuid;
  _persistentUuid = uuid;
}
```

## 7. Connection Quality Monitoring

**VDO.Ninja behavior:**
- Monitors packet loss and RTT
- Triggers reconnection on poor quality
- Adaptive quality thresholds

**Implementation needed:**
```dart
Timer? _qualityMonitorTimer;

void _startQualityMonitoring(String uuid) {
  _qualityMonitorTimer = Timer.periodic(Duration(seconds: 10), () async {
    final pc = _peerConnections[uuid];
    if (pc == null) return;
    
    try {
      final stats = await pc.getStats();
      double packetLoss = 0;
      double rtt = 0;
      
      // Parse WebRTC stats
      for (var stat in stats) {
        if (stat.type == 'candidate-pair' && stat.values['state'] == 'succeeded') {
          rtt = (stat.values['currentRoundTripTime'] ?? 0) * 1000;
        }
        if (stat.type == 'inbound-rtp') {
          final packetsLost = stat.values['packetsLost'] ?? 0;
          final packetsReceived = stat.values['packetsReceived'] ?? 0;
          if (packetsReceived > 0) {
            packetLoss = (packetsLost / (packetsLost + packetsReceived)) * 100;
          }
        }
      }
      
      // Trigger reconnection on poor quality
      if (packetLoss > 10 || rtt > 500) {
        print('[SocialStream] Poor connection quality - Loss: ${packetLoss.toStringAsFixed(1)}%, RTT: ${rtt.toStringAsFixed(0)}ms');
        _handleConnectionFailure(uuid);
      }
    } catch (e) {
      print('[SocialStream] Error monitoring quality: $e');
    }
  });
}
```

## Summary

To match VDO.Ninja's robust reconnection behavior, Social Stream needs:

1. **Automatic WebSocket reconnection** with exponential backoff
2. **Platform-specific timeouts** (Windows vs others)
3. **ICE restart capability** for connection recovery
4. **Network change monitoring** for proactive reconnection
5. **Safari/iOS heartbeat workaround** for connection detection
6. **Session persistence** across reconnections
7. **Connection quality monitoring** with adaptive thresholds

These improvements will significantly enhance reliability, especially on unstable networks or during network transitions (WiFi to cellular, etc.).

## Dependencies Needed

Add to pubspec.yaml:
```yaml
dependencies:
  connectivity_plus: ^5.0.0
```

## Testing Scenarios

1. **Network interruption**: Disconnect WiFi/ethernet for 10+ seconds
2. **WebSocket server restart**: Kill and restart the signaling server
3. **ICE failure**: Block STUN/TURN servers temporarily
4. **Platform differences**: Test on Windows vs macOS/iOS
5. **Poor network**: Simulate high packet loss/latency
6. **Network switching**: Switch between WiFi and cellular