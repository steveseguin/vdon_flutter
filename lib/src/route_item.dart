import 'package:flutter/material.dart';
import 'dart:core';

typedef void RouteCallback(BuildContext context);

class RouteItem {
  RouteItem({
    @required this.title,
    @required this.subtitle,
    @required this.icon,
    @required this.push,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final RouteCallback push;
}