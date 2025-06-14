// obs_controls.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../models/obs_state.dart';

// Status bar widget - always visible at top
class OBSStatusBar extends StatelessWidget {
  final Map<String, OBSState> obsStates;
  
  const OBSStatusBar({
    Key? key,
    required this.obsStates,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (obsStates.isEmpty) return SizedBox.shrink();
    
    // Get the first OBS state for now (could expand to handle multiple)
    final obsState = obsStates.values.first;
    
    // Determine status
    bool isRecording = obsState.recording == true;
    bool isStreaming = obsState.streaming == true;
    bool isVisible = obsState.visibility == true;
    bool isActive = obsState.sourceActive == true;
    bool hasVirtualCam = obsState.virtualcam == true;
    String? currentScene = obsState.details?.currentSceneName;
    
    // Determine color - now with transparency
    Color barColor = Colors.grey.withOpacity(0.7);
    if (isRecording || isStreaming) {
      // If recording/streaming but not active, use brown/orange
      if (!isActive) {
        barColor = Colors.orange.shade800.withOpacity(0.8);
      } else {
        barColor = Colors.red.withOpacity(0.8);
      }
    } else if (hasVirtualCam) {
      barColor = Colors.orange.withOpacity(0.8);
    } else if (isVisible && isActive) {
      barColor = Colors.green.withOpacity(0.8);
    }
    
    return Container(
      height: 28,
      width: double.infinity,
      decoration: BoxDecoration(
        color: barColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording indicator with live dot
          if (isRecording)
            _buildLiveIndicator('REC', Colors.red),
          
          // Streaming indicator with live dot
          if (isStreaming)
            _buildLiveIndicator('LIVE', Colors.red),
            
          // Virtual cam indicator with active dot
          if (hasVirtualCam)
            _buildLiveIndicator('VCAM', Colors.orange),
          
          // Active/Inactive status
          if (!isRecording && !isStreaming && !hasVirtualCam) ...[
            Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.green : Colors.grey,
                boxShadow: isActive ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.6),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ] : null,
              ),
            ),
            Text(
              isActive ? 'ACTIVE' : 'INACTIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          
          // Visibility indicator
          if (isVisible != null) ...[
            SizedBox(width: 12),
            Icon(
              isVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.white.withOpacity(0.8),
              size: 16,
            ),
          ],
          
          // Scene name
          if (currentScene != null) ...[
            SizedBox(width: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                currentScene,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildLiveIndicator(String label, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing red dot for live/recording
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Control button widget - only visible when control level >= 4
class OBSControlsWidget extends StatefulWidget {
  final OBSState obsState;
  final String peerUuid;
  final Function(String action, {String? value}) onCommand;
  final bool hasControl;
  
  const OBSControlsWidget({
    Key? key,
    required this.obsState,
    required this.peerUuid,
    required this.onCommand,
    required this.hasControl,
  }) : super(key: key);
  
  @override
  _OBSControlsWidgetState createState() => _OBSControlsWidgetState();
}

class _OBSControlsWidgetState extends State<OBSControlsWidget> with AutomaticKeepAliveClientMixin {
  bool _isExpanded = false;
  DateTime? _lastRefresh;
  bool _isProcessing = false;
  DateTime _lastButtonPress = DateTime.now();
  static const Duration _debounceDuration = Duration(milliseconds: 500);
  
  @override
  bool get wantKeepAlive => true;
  
  // Debounced command handler
  void _handleCommand(String action, {String? value}) {
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastButtonPress) < _debounceDuration) {
      print("Ignoring rapid button press");
      return;
    }
    
    print("OBS Control button pressed: $action${value != null ? ' with value: $value' : ''}");
    
    setState(() {
      _isProcessing = true;
      _lastButtonPress = now;
    });
    
    widget.onCommand(action, value: value);
    
    // Reset processing flag after a delay
    Future.delayed(_debounceDuration, () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Check control level - need level >= 4 to show controls
    final controlLevel = widget.obsState.details?.controlLevel ?? 0;
    
    // If we're receiving OBS state updates (recording, streaming, etc), 
    // assume we have control access even if controlLevel isn't set yet
    bool hasOBSStateData = widget.obsState.recording != null ||
                          widget.obsState.streaming != null ||
                          widget.obsState.virtualcam != null ||
                          widget.obsState.visibility != null ||
                          widget.obsState.sourceActive != null;
    
    // Show controls if we have explicit control level >= 4 OR we're receiving OBS state data
    bool shouldShowControls = controlLevel >= 4 || hasOBSStateData;
    
    if (!shouldShowControls) {
      return SizedBox.shrink();
    }
    
    // Check if we have any controls to show
    bool hasControls = widget.obsState.recording != null ||
                      widget.obsState.streaming != null ||
                      widget.obsState.virtualcam != null ||
                      (widget.obsState.details?.scenes != null && 
                       widget.obsState.details!.scenes!.isNotEmpty);
    
    // Always show the button if we're getting OBS data, even if specific controls aren't available yet
    // This allows users to expand and see the status
    
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: _isExpanded ? 280 : 60,
      constraints: BoxConstraints(
        maxHeight: _isExpanded ? 400 : 60,
      ),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.purple, width: 2),
      ),
      child: _isExpanded ? _buildExpandedControls() : _buildCollapsedControls(),
    );
  }
  
  Widget _buildCollapsedControls() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _isExpanded = true);
        // Request fresh OBS state when expanding (rate limited to once per 5 seconds)
        final now = DateTime.now();
        if (_lastRefresh == null || now.difference(_lastRefresh!).inSeconds > 5) {
          _lastRefresh = now;
          widget.onCommand('refreshState');
        }
      },
      child: Container(
        height: 60,
        width: 60,
        alignment: Alignment.center,
        child: Icon(
          Icons.gamepad,
          color: Colors.purple,
          size: 30,
        ),
      ),
    );
  }
  
  Widget _buildExpandedControls() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.purple.withOpacity(0.3))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'OBS Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white70),
                  onPressed: () => setState(() => _isExpanded = false),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
          
          // Control buttons
          Container(
            padding: EdgeInsets.all(12),
            child: Column(
              children: [
                // Info text if we don't have full state yet
                if (widget.obsState.recording == null && 
                    widget.obsState.streaming == null && 
                    widget.obsState.virtualcam == null)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Limited OBS data received.\nTry the refresh button below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                
                // Always show recording control
                _buildControlButton(
                  label: (widget.obsState.recording == true) ? 'Stop Recording' : 'Start Recording',
                  icon: Icons.fiber_manual_record,
                  isActive: widget.obsState.recording == true,
                  enabled: true, // Always enabled if we have OBS state
                  onPressed: () => _handleCommand(
                    (widget.obsState.recording == true) ? 'stopRecording' : 'startRecording'
                  ),
                ),
                
                // Always show streaming control
                _buildControlButton(
                  label: (widget.obsState.streaming == true) ? 'Stop Streaming' : 'Start Streaming',
                  icon: Icons.stream,
                  isActive: widget.obsState.streaming == true,
                  enabled: true, // Always enabled if we have OBS state
                  onPressed: () => _handleCommand(
                    (widget.obsState.streaming == true) ? 'stopStreaming' : 'startStreaming'
                  ),
                ),
                
                // Virtual camera control
                if (widget.obsState.virtualcam != null)
                  _buildControlButton(
                    label: widget.obsState.virtualcam! ? 'Stop Virtual Cam' : 'Start Virtual Cam',
                    icon: Icons.camera,
                    isActive: widget.obsState.virtualcam!,
                    enabled: true,
                    onPressed: () => _handleCommand(
                      widget.obsState.virtualcam! ? 'stopVirtualcam' : 'startVirtualcam'
                    ),
                  ),
                  
                // Debug: Refresh button to request full state
                SizedBox(height: 8),
                TextButton.icon(
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text('Refresh OBS State', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.purple,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  onPressed: () => _handleCommand('refreshState'),
                ),
              ],
            ),
          ),
          
          // Scene selector or waiting message
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.purple.withOpacity(0.3))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scenes',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                if (widget.obsState.details?.scenes != null && 
                    widget.obsState.details!.scenes!.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.obsState.details!.scenes!.map((scene) {
                      final isActive = scene == widget.obsState.details!.currentSceneName;
                      return GestureDetector(
                        onTap: () => _handleCommand('setCurrentScene', value: scene),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.purple : Colors.transparent,
                            border: Border.all(
                              color: isActive ? Colors.purple : Colors.purple.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            scene,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                else
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No scenes available\n(Requires OBS control permission)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required bool isActive,
    bool enabled = true,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !_isProcessing ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: !enabled
                ? Colors.red.withOpacity(0.1)  // Red tint when disabled
                : isActive 
                  ? Colors.green.withOpacity(0.2)  // Green background when active
                  : Colors.grey.withOpacity(0.2),  // Grey background when inactive
              border: Border.all(
                color: !enabled
                  ? Colors.red.withOpacity(0.5)  // Red border when disabled
                  : isActive 
                    ? Colors.green  // Green border when active
                    : Colors.grey.shade600,  // Grey border when inactive
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (_isProcessing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isActive ? Colors.green : Colors.grey,
                      ),
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: !enabled
                      ? Colors.red.withOpacity(0.5)
                      : isActive 
                        ? Colors.green
                        : Colors.grey.shade400,
                    size: 20,
                  ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Expanded panel widget - used when controls are triggered from app bar
class OBSControlsExpandedPanel extends StatefulWidget {
  final OBSState obsState;
  final String peerUuid;
  final int controlLevel;
  final Function(String action, {String? value}) onCommand;
  final VoidCallback onClose;
  
  const OBSControlsExpandedPanel({
    Key? key,
    required this.obsState,
    required this.peerUuid,
    required this.controlLevel,
    required this.onCommand,
    required this.onClose,
  }) : super(key: key);
  
  @override
  _OBSControlsExpandedPanelState createState() => _OBSControlsExpandedPanelState();
}

class _OBSControlsExpandedPanelState extends State<OBSControlsExpandedPanel> {
  DateTime? _lastRefresh;
  bool _isProcessing = false;
  DateTime _lastButtonPress = DateTime.now();
  static const Duration _debounceDuration = Duration(milliseconds: 500);
  
  Timer? _periodicRefreshTimer;
  
  @override
  void initState() {
    super.initState();
    // Request fresh OBS state when panel opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshState();
    });
    
    // Set up periodic refresh to catch permission changes
    _periodicRefreshTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (mounted) {
        _refreshState();
      }
    });
  }
  
  @override
  void dispose() {
    _periodicRefreshTimer?.cancel();
    super.dispose();
  }
  
  void _refreshState() {
    final now = DateTime.now();
    if (_lastRefresh == null || now.difference(_lastRefresh!).inSeconds > 5) {
      _lastRefresh = now;
      widget.onCommand('refreshState');
    }
  }
  
  // Debounced command handler
  void _handleCommand(String action, {String? value}) {
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastButtonPress) < _debounceDuration) {
      print("Ignoring rapid button press");
      return;
    }
    
    print("OBS Control button pressed: $action${value != null ? ' with value: $value' : ''}");
    
    setState(() {
      _isProcessing = true;
      _lastButtonPress = now;
    });
    
    widget.onCommand(action, value: value);
    
    // Reset processing flag after a delay
    Future.delayed(_debounceDuration, () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    });
  }
  
  String _getControlLevelDescription(int level) {
    switch (level) {
      case 1:
      case 2:
      case 3:
        return 'View Only';
      case 4:
        return 'Scene Control';
      case 5:
        return 'Full Control';
      default:
        return 'No Access';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.purple.withOpacity(0.3))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OBS Controls',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Level ${widget.controlLevel}: ${_getControlLevelDescription(widget.controlLevel)}',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white70),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
          
          // Control buttons - only show if control level is 5 (full control)
          if (widget.controlLevel >= 5) Container(
            padding: EdgeInsets.all(12),
            child: Column(
              children: [
                // Info text if we don't have full state yet
                if (widget.obsState.recording == null && 
                    widget.obsState.streaming == null && 
                    widget.obsState.virtualcam == null)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Limited OBS data received.\nTry the refresh button below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                
                // Recording control
                _buildControlButton(
                  label: (widget.obsState.recording == true) ? 'Stop Recording' : 'Start Recording',
                  icon: Icons.fiber_manual_record,
                  isActive: widget.obsState.recording == true,
                  enabled: true,
                  onPressed: () => _handleCommand(
                    (widget.obsState.recording == true) ? 'stopRecording' : 'startRecording'
                  ),
                ),
                
                // Streaming control
                _buildControlButton(
                  label: (widget.obsState.streaming == true) ? 'Stop Streaming' : 'Start Streaming',
                  icon: Icons.stream,
                  isActive: widget.obsState.streaming == true,
                  enabled: true,
                  onPressed: () => _handleCommand(
                    (widget.obsState.streaming == true) ? 'stopStreaming' : 'startStreaming'
                  ),
                ),
                
                // Virtual camera control
                if (widget.obsState.virtualcam != null)
                  _buildControlButton(
                    label: widget.obsState.virtualcam! ? 'Stop Virtual Cam' : 'Start Virtual Cam',
                    icon: Icons.camera,
                    isActive: widget.obsState.virtualcam!,
                    enabled: true,
                    onPressed: () => _handleCommand(
                      widget.obsState.virtualcam! ? 'stopVirtualcam' : 'startVirtualcam'
                    ),
                  ),
                  
                // Refresh button
                SizedBox(height: 8),
                TextButton.icon(
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text('Refresh OBS State', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.purple,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  onPressed: () => _handleCommand('refreshState'),
                ),
              ],
            ),
          ),
          
          // Scene selector - only show if control level is 4 or higher
          if (widget.controlLevel >= 4) Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.purple.withOpacity(0.3))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scenes',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                if (widget.obsState.details?.scenes != null && 
                    widget.obsState.details!.scenes!.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.obsState.details!.scenes!.map((scene) {
                      final isActive = scene == widget.obsState.details!.currentSceneName;
                      return GestureDetector(
                        onTap: () => _handleCommand('setCurrentScene', value: scene),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.purple : Colors.transparent,
                            border: Border.all(
                              color: isActive ? Colors.purple : Colors.purple.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            scene,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                else
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No scenes available\n(Requires OBS control permission)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // View-only message for lower permission levels
          if (widget.controlLevel < 4)
            Container(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility,
                      color: Colors.white54,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'View Only Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You can see the OBS status but cannot make changes.\nHigher permissions are required for control access.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required bool isActive,
    bool enabled = true,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !_isProcessing ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: !enabled
                ? Colors.red.withOpacity(0.1)  // Red tint when disabled
                : isActive 
                  ? Colors.green.withOpacity(0.2)  // Green background when active
                  : Colors.grey.withOpacity(0.2),  // Grey background when inactive
              border: Border.all(
                color: !enabled
                  ? Colors.red.withOpacity(0.5)  // Red border when disabled
                  : isActive 
                    ? Colors.green  // Green border when active
                    : Colors.grey.shade600,  // Grey border when inactive
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (_isProcessing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isActive ? Colors.green : Colors.grey,
                      ),
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: !enabled
                      ? Colors.red.withOpacity(0.5)
                      : isActive 
                        ? Colors.green
                        : Colors.grey.shade400,
                    size: 20,
                  ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}