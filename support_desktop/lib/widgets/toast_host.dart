import 'package:flutter/material.dart';

Widget toastHost(Widget child) => Scaffold(
  backgroundColor: Colors.transparent,
  resizeToAvoidBottomInset: false,
  body: child,
);
