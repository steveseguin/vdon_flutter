// performance_monitor.dart
import 'dart:async';
import 'package:flutter/material.dart';

class PerformanceMonitor {
  // FPS tracking
  int _frameCount = 0;
  DateTime _lastFPSCheck = DateTime.now();
  double _currentFPS = 30.0;
  double _averageFPS = 30.0;
  List<double> _fpsHistory = [];
  static const int _fpsHistorySize = 10;
  
  // Memory tracking
  int _lastMemoryUsage = 0;
  
  // CPU tracking (approximated by frame drops)
  int _droppedFrames = 0;
  int _totalFrames = 0;
  
  // Callbacks
  Function(PerformanceStats)? onStatsUpdate;
  Function()? onLowPerformance;
  
  // Timers
  Timer? _statsTimer;
  Timer? _memoryTimer;
  
  // Thresholds
  static const double lowFPSThreshold = 20.0;
  static const double criticalFPSThreshold = 15.0;
  static const int highMemoryThresholdMB = 200;
  
  void startMonitoring() {
    // Update stats every second
    _statsTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _updateStats();
    });
    
    // Check memory less frequently
    _memoryTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkMemoryUsage();
    });
  }
  
  void stopMonitoring() {
    _statsTimer?.cancel();
    _memoryTimer?.cancel();
  }
  
  void trackFrame() {
    _frameCount++;
    _totalFrames++;
    
    final now = DateTime.now();
    final elapsed = now.difference(_lastFPSCheck).inMilliseconds;
    
    if (elapsed >= 1000) {
      _currentFPS = (_frameCount * 1000 / elapsed).clamp(0, 60);
      _frameCount = 0;
      _lastFPSCheck = now;
      
      // Update FPS history
      _fpsHistory.add(_currentFPS);
      if (_fpsHistory.length > _fpsHistorySize) {
        _fpsHistory.removeAt(0);
      }
      
      // Calculate average FPS
      if (_fpsHistory.isNotEmpty) {
        _averageFPS = _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;
      }
      
      // Check for performance issues
      if (_currentFPS < criticalFPSThreshold) {
        onLowPerformance?.call();
      }
    }
  }
  
  void trackDroppedFrame() {
    _droppedFrames++;
  }
  
  void _updateStats() {
    final stats = PerformanceStats(
      currentFPS: _currentFPS,
      averageFPS: _averageFPS,
      droppedFrames: _droppedFrames,
      totalFrames: _totalFrames,
      memoryUsageMB: _lastMemoryUsage,
      dropRate: _totalFrames > 0 ? _droppedFrames / _totalFrames : 0,
    );
    
    onStatsUpdate?.call(stats);
  }
  
  void _checkMemoryUsage() {
    // This is a placeholder - actual memory usage tracking would require
    // platform-specific code or a plugin
    // For now, we'll estimate based on frame drops and FPS
    if (_averageFPS < lowFPSThreshold) {
      _lastMemoryUsage = highMemoryThresholdMB + 50; // Simulate high memory
    } else {
      _lastMemoryUsage = 100; // Normal memory usage
    }
  }
  
  PerformanceRecommendation getRecommendation() {
    if (_averageFPS < criticalFPSThreshold) {
      return PerformanceRecommendation(
        action: PerformanceAction.reduceQuality,
        reason: 'Very low FPS detected',
        targetBitrate: 2000,
        targetFramerate: 15,
      );
    } else if (_averageFPS < lowFPSThreshold) {
      return PerformanceRecommendation(
        action: PerformanceAction.reduceQuality,
        reason: 'Low FPS detected',
        targetBitrate: 4000,
        targetFramerate: 20,
      );
    } else if (_droppedFrames > _totalFrames * 0.1) {
      return PerformanceRecommendation(
        action: PerformanceAction.reduceQuality,
        reason: 'High frame drop rate',
        targetBitrate: 5000,
        targetFramerate: 25,
      );
    }
    
    return PerformanceRecommendation(
      action: PerformanceAction.maintain,
      reason: 'Performance is good',
    );
  }
  
  void reset() {
    _frameCount = 0;
    _droppedFrames = 0;
    _totalFrames = 0;
    _fpsHistory.clear();
    _currentFPS = 30.0;
    _averageFPS = 30.0;
  }
  
  void dispose() {
    stopMonitoring();
  }
}

class PerformanceStats {
  final double currentFPS;
  final double averageFPS;
  final int droppedFrames;
  final int totalFrames;
  final int memoryUsageMB;
  final double dropRate;
  
  PerformanceStats({
    required this.currentFPS,
    required this.averageFPS,
    required this.droppedFrames,
    required this.totalFrames,
    required this.memoryUsageMB,
    required this.dropRate,
  });
  
  bool get isLowPerformance => averageFPS < PerformanceMonitor.lowFPSThreshold;
  bool get isCriticalPerformance => averageFPS < PerformanceMonitor.criticalFPSThreshold;
}

class PerformanceRecommendation {
  final PerformanceAction action;
  final String reason;
  final int? targetBitrate;
  final int? targetFramerate;
  
  PerformanceRecommendation({
    required this.action,
    required this.reason,
    this.targetBitrate,
    this.targetFramerate,
  });
}

enum PerformanceAction {
  maintain,
  reduceQuality,
  increaseQuality,
}