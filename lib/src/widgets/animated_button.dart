// animated_button.dart
import 'package:flutter/material.dart';

class AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final Color fillColor;
  final ShapeBorder shape;
  final double elevation;
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;
  final VisualDensity visualDensity;

  const AnimatedButton({
    Key? key,
    required this.child,
    required this.onPressed,
    required this.fillColor,
    this.shape = const CircleBorder(),
    this.elevation = 2,
    this.padding = const EdgeInsets.all(15),
    this.constraints = const BoxConstraints(minWidth: 51),
    this.visualDensity = VisualDensity.comfortable,
  }) : super(key: key);

  @override
  _AnimatedButtonState createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _elevationAnimation = Tween<double>(
      begin: widget.elevation,
      end: widget.elevation / 2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: RawMaterialButton(
              constraints: widget.constraints,
              visualDensity: widget.visualDensity,
              onPressed: widget.onPressed,
              fillColor: widget.fillColor,
              child: widget.child,
              shape: widget.shape,
              elevation: _elevationAnimation.value,
              padding: widget.padding,
            ),
          );
        },
      ),
    );
  }
}