// chat_overlay.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/social_stream_service.dart';

class ChatOverlay extends StatefulWidget {
  final bool isVisible;
  final Stream<ChatMessage> chatStream;
  
  const ChatOverlay({
    Key? key,
    required this.isVisible,
    required this.chatStream,
  }) : super(key: key);
  
  @override
  _ChatOverlayState createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> with TickerProviderStateMixin {
  final List<_AnimatedChatMessage> _messages = [];
  final int _maxMessages = 10;
  late StreamSubscription<ChatMessage> _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscription = widget.chatStream.listen(_handleNewMessage);
  }
  
  @override
  void dispose() {
    _subscription.cancel();
    for (var message in _messages) {
      message.controller.dispose();
    }
    super.dispose();
  }
  
  void _handleNewMessage(ChatMessage message) {
    print('[ChatOverlay] === NEW MESSAGE RECEIVED ===');
    print('[ChatOverlay] Author: ${message.author}');
    print('[ChatOverlay] Content: ${message.content}');
    print('[ChatOverlay] Platform: ${message.platform}');
    print('[ChatOverlay] Widget visible: ${widget.isVisible}');
    
    if (!mounted) {
      print('[ChatOverlay] Widget not mounted, ignoring message');
      return;
    }
    
    setState(() {
      print('[ChatOverlay] Adding message to display list');
      
      // Create animated message
      final animatedMessage = _AnimatedChatMessage(
        message: message,
        controller: AnimationController(
          duration: Duration(milliseconds: 300),
          vsync: this,
        ),
      );
      
      // Start fade in animation
      animatedMessage.controller.forward();
      
      // Add to list
      _messages.add(animatedMessage);
      
      // Remove old messages if exceeding limit
      while (_messages.length > _maxMessages) {
        final oldMessage = _messages.removeAt(0);
        oldMessage.controller.dispose();
      }
      
      // Auto-remove message after delay
      Timer(Duration(seconds: 10), () {
        if (mounted && _messages.contains(animatedMessage)) {
          animatedMessage.controller.reverse().then((_) {
            if (mounted) {
              setState(() {
                _messages.remove(animatedMessage);
                animatedMessage.controller.dispose();
              });
            }
          });
        }
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    print('[ChatOverlay] === BUILD ===');
    print('[ChatOverlay] Visible: ${widget.isVisible}');
    print('[ChatOverlay] Messages count: ${_messages.length}');
    
    if (!widget.isVisible || _messages.isEmpty) {
      print('[ChatOverlay] Not visible or no messages, returning empty widget');
      return SizedBox.shrink();
    }
    
    print('[ChatOverlay] Rendering ${_messages.length} messages');
    
    return Positioned(
      left: 20,
      right: 20,
      bottom: 150, // Position above the control buttons
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _messages.map((animatedMessage) {
          return FadeTransition(
            opacity: animatedMessage.controller,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(-1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animatedMessage.controller,
                curve: Curves.easeOut,
              )),
              child: _ChatMessageWidget(message: animatedMessage.message),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AnimatedChatMessage {
  final ChatMessage message;
  final AnimationController controller;
  
  _AnimatedChatMessage({
    required this.message,
    required this.controller,
  });
}

class _ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;
  
  const _ChatMessageWidget({
    Key? key,
    required this.message,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getPlatformColor(message.platform),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          if (message.avatarUrl != null)
            Container(
              width: 32,
              height: 32,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getPlatformColor(message.platform),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: Image.network(
                  message.avatarUrl!,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildDefaultAvatar();
                  },
                ),
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              margin: EdgeInsets.only(right: 8),
              child: _buildDefaultAvatar(),
            ),
          
          // Message content
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Platform icon
                    Icon(
                      _getPlatformIcon(message.platform),
                      size: 14,
                      color: _getPlatformColor(message.platform),
                    ),
                    SizedBox(width: 4),
                    // Author name
                    Flexible(
                      child: Text(
                        message.author,
                        style: TextStyle(
                          color: _getPlatformColor(message.platform),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                // Message text
                Text(
                  message.content,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getPlatformColor(message.platform).withOpacity(0.3),
      ),
      child: Center(
        child: Text(
          message.author.isNotEmpty ? message.author[0].toUpperCase() : '?',
          style: TextStyle(
            color: _getPlatformColor(message.platform),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
  
  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Colors.red;
      case 'twitch':
        return Colors.purple;
      case 'facebook':
        return Colors.blue;
      case 'twitter':
      case 'x':
        return Colors.lightBlue;
      case 'instagram':
        return Colors.pink;
      case 'tiktok':
        return Colors.pinkAccent;
      case 'discord':
        return Color(0xFF5865F2);
      default:
        return Colors.grey;
    }
  }
  
  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_filled;
      case 'twitch':
        return Icons.videogame_asset;
      case 'facebook':
        return Icons.facebook;
      case 'twitter':
      case 'x':
        return Icons.tag;
      case 'instagram':
        return Icons.camera_alt;
      case 'tiktok':
        return Icons.music_note;
      case 'discord':
        return Icons.discord;
      default:
        return Icons.chat_bubble;
    }
  }
}