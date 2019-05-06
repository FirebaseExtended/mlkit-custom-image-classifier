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

class ZeroStateDatasets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: SingleChildScrollView(
        child: new Column(
          children: <Widget>[
            new Padding(
              padding: EdgeInsets.only(
                  left: 20.0, top: 40.0, right: 20.0, bottom: 10.0),
              child: new Image.asset("images/artboard23.png"),
            ),
            Container(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                "Custom Image Classifier makes it easy to build custom image " +
                    "classification models from scratch. \n\nLet's get started by " +
                    "creating a dataset.",
                softWrap: true,
                style: TextStyle(fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
