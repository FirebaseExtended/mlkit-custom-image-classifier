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

import 'dart:async';
import 'dart:io';

import 'package:automl_mlkit/automl_mlkit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _modelLoadStatus = 'unknown';
  File _imageFile;
  String _inferenceResult;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  Future<void> loadModel() async {
    String dataset = "pens";
    await createLocalFiles(dataset);
    String modelLoadStatus;
    try {
      await AutomlMlkit.loadModelFromCache(dataset: dataset);
      modelLoadStatus = "AutoML model successfully loaded";
    } on PlatformException catch (e) {
      modelLoadStatus = "Error loading model";
      print("error from platform on calling loadModelFromCache");
      print(e.toString());
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _modelLoadStatus = modelLoadStatus;
    });
  }

  Future<void> createLocalFiles(String folder) async {
    Directory tempDir = await getTemporaryDirectory();
    final Directory modelDir = Directory("${tempDir.path}/$folder");
    if (!modelDir.existsSync()) {
      modelDir.createSync();
    }
    final filenames = ["manifest.json", "model.tflite", "dict.txt"];

    for (String filename in filenames) {
      final File file = File("${modelDir.path}/$filename");
      if (!file.existsSync()) {
        print("Copying file: $filename");
        await copyFileFromAssets(filename, file);
      }
    }
  }

  /// copies file from assets to dst file
  Future<void> copyFileFromAssets(String filename, File dstFile) async {
    ByteData data = await rootBundle.load("assets/$filename");
    final buffer = data.buffer;
    dstFile.writeAsBytesSync(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Future<void> loadImageAndInfer() async {
    final File imageFile =
        await ImagePicker.pickImage(source: ImageSource.gallery);

    if (imageFile == null) {
      Scaffold.of(context)
          .showSnackBar(SnackBar(content: Text("Can't read image")));
      return;
    }

    final results =
        await AutomlMlkit.runModelOnImage(imagePath: imageFile.path);
    print("Got results" + results[0].toString());
    if (results.isEmpty) {
      Scaffold.of(context)
          .showSnackBar(SnackBar(content: Text("No labels found")));
    } else {
      final label = results[0]["label"];
      final confidence = (results[0]["confidence"] * 100).toStringAsFixed(2);
      setState(() {
        _imageFile = imageFile;
        _inferenceResult = "$label: $confidence \%";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin App'),
        ),
        body: Builder(
          builder: (BuildContext context) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _inferenceResult == null
                      ? Container()
                      : Text(
                          "$_inferenceResult",
                          style: TextStyle(fontSize: 20),
                        ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _imageFile == null
                        ? Container()
                        : Container(
                            height: 200,
                            child: Image.file(_imageFile),
                          ),
                  ),
                  FlatButton(
                    color: Colors.blue[600],
                    onPressed: loadImageAndInfer,
                    textColor: Colors.white,
                    child: Text("CHOOSE A PHOTO"),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text('Model load status: $_modelLoadStatus\n'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
