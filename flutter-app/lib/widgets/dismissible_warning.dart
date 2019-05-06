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

/// Widget that shows a warning if the video requirements for this label are
/// not met
class DismissibleMessageWidget extends StatefulWidget {
  final String msg;
  final IconData icon;
  final Color color;
  final Color textColor;

  const DismissibleMessageWidget({
    this.msg,
    this.icon = Icons.info_outline,
    this.color = Colors.blueGrey,
    this.textColor = Colors.white,
  });

  @override
  DismissibleMessageWidgetState createState() {
    return new DismissibleMessageWidgetState();
  }
}

class DismissibleMessageWidgetState extends State<DismissibleMessageWidget> {
  var _isDismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return Container();
    }
    return Container(
      color: widget.color,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4, left: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(widget.icon, color: widget.textColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  widget.msg,
                  style: TextStyle(color: widget.textColor),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close),
              color: widget.textColor,
              onPressed: () {
                setState(() {
                  _isDismissed = true;
                });
              },
            )
          ],
        ),
      ),
    );
  }
}
