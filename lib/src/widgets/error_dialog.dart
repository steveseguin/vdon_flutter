// error_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? details;
  final List<ErrorAction> actions;
  
  const ErrorDialog({
    Key? key,
    required this.title,
    required this.message,
    this.details,
    this.actions = const [],
  }) : super(key: key);
  
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String? details,
    List<ErrorAction>? actions,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ErrorDialog(
          title: title,
          message: message,
          details: details,
          actions: actions ?? [
            ErrorAction(
              label: 'OK',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.redAccent,
            size: 28,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            if (details != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Technical Details',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy, size: 16),
                          color: Colors.white54,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: details));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Details copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      details!,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 16),
            _buildTroubleshootingTips(),
          ],
        ),
      ),
      actions: actions.map((action) {
        return TextButton(
          child: Text(
            action.label,
            style: TextStyle(
              color: action.isPrimary ? Colors.blueAccent : Colors.white70,
              fontWeight: action.isPrimary ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          onPressed: () {
            if (action.dismissDialog) {
              Navigator.of(context).pop();
            }
            action.onPressed();
          },
        );
      }).toList(),
    );
  }
  
  Widget _buildTroubleshootingTips() {
    List<String> tips = _getTroubleshootingTips();
    
    if (tips.isEmpty) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Colors.blueAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Troubleshooting Tips',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ...tips.map((tip) => Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: Colors.white70)),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
  
  List<String> _getTroubleshootingTips() {
    List<String> tips = [];
    
    if (message.toLowerCase().contains('connection') || 
        message.toLowerCase().contains('network')) {
      tips.addAll([
        'Check your internet connection',
        'Try disabling VPN if you\'re using one',
        'Restart your WiFi router',
        'Try using mobile data instead of WiFi',
      ]);
    }
    
    if (message.toLowerCase().contains('permission')) {
      tips.addAll([
        'Go to Settings > Apps > VDO.Ninja',
        'Enable Camera and Microphone permissions',
        'Restart the app after granting permissions',
      ]);
    }
    
    if (message.toLowerCase().contains('camera') || 
        message.toLowerCase().contains('video')) {
      tips.addAll([
        'Make sure no other app is using the camera',
        'Try restarting your device',
        'Check if camera works in other apps',
      ]);
    }
    
    return tips;
  }
}

class ErrorAction {
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool dismissDialog;
  
  ErrorAction({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.dismissDialog = true,
  });
}