// network_monitor.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Callbacks
  Function()? onConnectionLost;
  Function()? onConnectionRestored;
  Function(NetworkQuality)? onQualityChanged;
  
  // State
  bool _wasConnected = true;
  NetworkQuality _currentQuality = NetworkQuality.good;
  Timer? _qualityCheckTimer;
  
  // Stats for quality monitoring
  int _packetsSent = 0;
  int _packetsLost = 0;
  double _averageRtt = 0;
  
  void startMonitoring() {
    // Monitor connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _handleConnectivityChange(result);
      },
    );
    
    // Start quality monitoring
    _qualityCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkNetworkQuality();
    });
    
    // Check initial connectivity
    _checkInitialConnectivity();
  }
  
  void stopMonitoring() {
    _connectivitySubscription?.cancel();
    _qualityCheckTimer?.cancel();
  }
  
  void updateStats({
    required int packetsSent,
    required int packetsLost,
    required double rtt,
  }) {
    _packetsSent = packetsSent;
    _packetsLost = packetsLost;
    _averageRtt = rtt;
  }
  
  NetworkQuality get currentQuality => _currentQuality;
  
  void _handleConnectivityChange(ConnectivityResult result) {
    bool isConnected = result != ConnectivityResult.none;
    
    if (!isConnected && _wasConnected) {
      _wasConnected = false;
      onConnectionLost?.call();
    } else if (isConnected && !_wasConnected) {
      _wasConnected = true;
      onConnectionRestored?.call();
    }
  }
  
  Future<void> _checkInitialConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _handleConnectivityChange(result);
  }
  
  void _checkNetworkQuality() {
    NetworkQuality newQuality;
    
    if (_packetsSent == 0) {
      newQuality = NetworkQuality.unknown;
    } else {
      double lossPercent = (_packetsLost / _packetsSent) * 100;
      
      if (lossPercent > 5 || _averageRtt > 300) {
        newQuality = NetworkQuality.poor;
      } else if (lossPercent > 2 || _averageRtt > 150) {
        newQuality = NetworkQuality.fair;
      } else if (lossPercent > 0.5 || _averageRtt > 50) {
        newQuality = NetworkQuality.good;
      } else {
        newQuality = NetworkQuality.excellent;
      }
    }
    
    if (newQuality != _currentQuality) {
      _currentQuality = newQuality;
      onQualityChanged?.call(newQuality);
    }
  }
  
  void dispose() {
    stopMonitoring();
  }
}

enum NetworkQuality {
  unknown,
  excellent,
  good,
  fair,
  poor,
}

extension NetworkQualityExtension on NetworkQuality {
  String get displayName {
    switch (this) {
      case NetworkQuality.excellent:
        return 'Excellent';
      case NetworkQuality.good:
        return 'Good';
      case NetworkQuality.fair:
        return 'Fair';
      case NetworkQuality.poor:
        return 'Poor';
      case NetworkQuality.unknown:
        return 'Unknown';
    }
  }
  
  int get barCount {
    switch (this) {
      case NetworkQuality.excellent:
        return 4;
      case NetworkQuality.good:
        return 3;
      case NetworkQuality.fair:
        return 2;
      case NetworkQuality.poor:
        return 1;
      case NetworkQuality.unknown:
        return 0;
    }
  }
}