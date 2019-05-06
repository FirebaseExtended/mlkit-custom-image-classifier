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
import 'package:intro_slider/intro_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IntroTutorial extends StatefulWidget {
  static const routeName = '/tutorial';

  IntroTutorial({Key key}) : super(key: key);

  @override
  _IntroTutorialState createState() => _IntroTutorialState();
}

class _IntroTutorialState extends State<IntroTutorial> {
  List<Slide> slides = new List();

  @override
  void initState() {
    super.initState();

    slides.add(
      new Slide(
        title: "USE",
        description: "Use image classification ML models to classify the world around you.",
        pathImage: "images/use.png",
        backgroundColor: Colors.deepPurple,
      ),
    );
    slides.add(
      new Slide(
        title: "COLLABORATE",
        description:
            "Collaborate on models and improve them with better datasets",
        pathImage: "images/collaborate.png",
        backgroundColor: Colors.deepPurple,
      ),
    );
    slides.add(new Slide(
      title: "CREATE",
      description: "Create your own models easily from the app",
      pathImage: "images/camera.png",
      backgroundColor: Colors.deepPurple,
    ));
  }

  void onDonePress() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenTutorial', true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: new IntroSlider(
        slides: this.slides,
        onDonePress: onDonePress,
      ),
    );
  }
}
