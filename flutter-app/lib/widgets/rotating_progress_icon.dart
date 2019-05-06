// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';
import 'dart:math' as math;

class RotatingProgressIcon extends StatefulWidget {
  @override
  _RotatingProgressIconState createState() => _RotatingProgressIconState();
}

class _RotatingProgressIconState extends State<RotatingProgressIcon>
    with SingleTickerProviderStateMixin {
  AnimationController controller;

  final Tween<double> tween = Tween<double>(begin: math.pi, end: 0);

  @override
  void initState() {
    super.initState();
    controller = new AnimationController(
        vsync: this, duration: new Duration(milliseconds: 800))
      ..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: Icon(Icons.cached),
      builder: (BuildContext context, Widget _widget) {
        return Transform.rotate(
            angle: tween.evaluate(controller), child: _widget);
      },
    );
  }
}
