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
import 'dart:convert';
import 'dart:io';

import 'package:automl_mlkit/automl_mlkit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'labelscreen.dart';
import 'models.dart';
import 'storage.dart';
import 'user_model.dart';
import 'widgets/zerostate_datasets.dart';

class DatasetsList extends StatelessWidget {
  final Query query;
  final UserModel model;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const DatasetsList({Key key, this.query, this.model, this.scaffoldKey})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return new StreamBuilder(
      stream: query.snapshots(),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return new Text('Error: ${snapshot.error}');
        }
        switch (snapshot.connectionState) {
          case ConnectionState.waiting:
            return Center(child: new CircularProgressIndicator());
          default:
            if (snapshot.data.documents.isEmpty) {
              return ZeroStateDatasets();
            }

            final filteredDatasets = snapshot.data.documents
                .map(Dataset.fromDocument)
                .where((dataset) =>
                    dataset.isPublic ||
                    dataset.isOwner(model) ||
                    dataset.isCollaborator(model));

            if (filteredDatasets.isEmpty) {
              return ZeroStateDatasets();
            }

            return new ListView(
                children: filteredDatasets
                    .map(
                      (dataset) => new Container(
                            decoration: new BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(color: Colors.grey[300])),
                            ),
                            height: 80,
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        new ListLabelsScreen(dataset),
                                  ),
                                );
                              },
                              child: new DatasetActions(
                                  dataset, model, scaffoldKey),
                            ),
                          ),
                    )
                    .toList());
        }
      },
    );
  }
}

const Map<String, String> MANIFEST_JSON_CONTENTS = {
  "modelFile": "model.tflite",
  "labelsFile": "dict.txt",
  "modelType": "IMAGE_LABELING"
};

class DatasetActions extends StatelessWidget {
  // Firestore id of the dataset for which model status is requested
  final Dataset dataset;
  final UserModel model;
  final GlobalKey<ScaffoldState> scaffoldKey;

  void _showSnackBar(String text) {
    scaffoldKey.currentState.showSnackBar(SnackBar(content: new Text(text)));
  }

  const DatasetActions(this.dataset, this.model, this.scaffoldKey);

  Future _beginModelInferenceAsync(BuildContext context) async {
    _showSnackBar("Fetching latest model info");
    final autoMlStorage = InheritedStorage.of(context).autoMlStorage;
    await _downloadModel(dataset, autoMlStorage);
    await loadModel(dataset.automlId);
    await _getImageAndRunInferenceAsync(context);
  }

  Future _getImageAndRunInferenceAsync(BuildContext context) async {
    final image = await getImage();
    final List inferences = await recognizeImage(image);

    // for debugging
    inferences.forEach((i) {
      print(("[Inference results] infer: ${i.toString()}"));
    });
    await _showInferenceDialog(context, inferences, image);
  }

  Future<void> _showInferenceDialog(
      BuildContext context, List<dynamic> inferences, File image) async {
    final retryInference = await showDialog<bool>(
        context: scaffoldKey.currentContext,
        builder: (BuildContext context) => InferenceDialog(image, inferences));

    // allow user to pick another image and retry inference
    if (retryInference) {
      await _getImageAndRunInferenceAsync(context);
    }
  }

  IconData getIcon(Dataset dataset) {
    if (dataset.isOwner(model)) {
      return Icons.person;
    }
    if (dataset.isCollaborator(model)) {
      return Icons.people;
    }
    if (dataset.isPublic) {
      return Icons.public;
    }
  }

  Color getColor(Dataset dataset) {
    if (dataset.isOwner(model)) {
      return Colors.teal;
    }
    if (dataset.isCollaborator(model)) {
      return Colors.pink[400];
    }
    if (dataset.isPublic) {
      return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool modelExists = false;
    String modelStatus = "No model available";

    return new StreamBuilder(
      stream: Firestore.instance
          .collection("models")
          .where("dataset_id", isEqualTo: dataset.automlId)
          .orderBy("generated_at", descending: true)
          .snapshots(),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return new Text('Loading...');

        if (snapshot.data.documents.isNotEmpty) {
          final modelInfo = snapshot.data.documents.first;
          final generatedAt =
              DateTime.fromMillisecondsSinceEpoch(modelInfo["generated_at"]);
          final ago = timeago.format(generatedAt);
          modelExists = true;
          modelStatus = "Last trained: " + ago;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    new Text(
                      dataset.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            getIcon(dataset),
                            size: 16,
                            color: Colors.black54,
                          ),
                          SizedBox(width: 4),
                          new Text(
                            dataset.description,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    ModelStatusInfo(
                      dataset: dataset,
                      modelStatus: modelStatus,
                      doesModelExist: modelExists,
                    )
                  ],
                ),
              ),
              new Row(
                children: <Widget>[
                  if (modelExists)
                    Container(
                      child: IconButton(
                        color: Colors.blueGrey,
                        icon: Icon(Icons.center_focus_weak),
                        tooltip: 'Run inference on an image',
                        onPressed: () async {
                          await _beginModelInferenceAsync(context);
                        },
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 1.0),
                        shape: BoxShape.circle,
                      ),
                    )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Future loadModel(String dataset) async {
    try {
      await AutomlMlkit.loadModelFromCache(dataset: dataset);
      print("Model successfully loaded");
    } on PlatformException catch (e) {
      print("failed to load model");
      print(e.toString());
    }
  }

  Future getImage() async {
    return ImagePicker.pickImage(source: ImageSource.camera);
  }

  Future<List<dynamic>> recognizeImage(File image) async {
    final results = await AutomlMlkit.runModelOnImage(imagePath: image.path);
    return results
        .map((result) => Inference.fromTfInference(result))
        .where((i) => i != null)
        .toList();
  }

  /// downloads the latest model for the given dataset from storage and saves
  /// it in system's temp directory
  Future<List<DownloadedModelInfo>> _downloadModel(
      Dataset dataset, FirebaseStorage autoMlStorage) async {
    final QuerySnapshot snapshot = await Firestore.instance
        .collection("models")
        .where("dataset_id", isEqualTo: dataset.automlId)
        .orderBy("generated_at", descending: true)
        .getDocuments();

    // reference to the latest model
    final modelInfo = snapshot.documents.first;

    final filesToDownload = {
      modelInfo["model"]: "model.tflite",
      modelInfo["label"]: "dict.txt",
    };

    final int generatedAt = modelInfo["generated_at"];

    // create a datasets dir in app's data folder
    final Directory appDocDir = await getTemporaryDirectory();
    final Directory modelDir =
        Directory("${appDocDir.path}/${dataset.automlId}");
    print("Using dir ${modelDir.path} for storing models");

    if (!modelDir.existsSync()) {
      modelDir.createSync();
    }

    // write a manifest.json for MLKit SDK
    final File manifestJsonFile = File('${modelDir.path}/manifest.json');
    if (!manifestJsonFile.existsSync()) {
      manifestJsonFile.writeAsString(jsonEncode(MANIFEST_JSON_CONTENTS));
    }
    // stores the timestamp at which the latest model was generated
    final File generatedAtFile = File('${modelDir.path}/generated_at');
    if (!generatedAtFile.existsSync()) {
      generatedAtFile.writeAsStringSync(modelInfo["generated_at"].toString());
    } else {
      // if the timestamp file exists, compare the timestamps to decide if the
      // model should be downloaded again.
      final storedTimestamp = int.parse(generatedAtFile.readAsStringSync());
      if (storedTimestamp >= generatedAt) {
        // newer (or same) model is stored, no need to download it again.
        print("[DatasetsList] Using cached model");
        return Future.value();
      }
    }

    // TODO: This will be replaced by the ML Kit Model Publishing API when it becomes available.
    final downloadFutures = filesToDownload.keys.map((filename) async {
      final outputFilename = filesToDownload[filename];
      print(
          "[DatasetsList] Attempting to download $filename at $outputFilename");

      final ref = autoMlStorage.ref().child("/$filename");

      // store model
      final File tempFile = File('${modelDir.path}/$outputFilename');
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      await tempFile.create();

      final StorageFileDownloadTask task = ref.writeToFile(tempFile);

      // return bytes downloaded
      final int byteCount = (await task.future).totalByteCount;
      return DownloadedModelInfo(tempFile.path, byteCount);
    }).toList();

    return Future.wait(downloadFutures);
  }
}

class InferenceDialog extends StatelessWidget {
  final File image;
  final List<dynamic> inferences;

  const InferenceDialog(this.image, this.inferences);

  @override
  Widget build(BuildContext context) {
    final labelsList = inferences
        .map((i) => new Text(
              "${i.label.toUpperCase()} ${i.confidence.toStringAsFixed(3)}",
              style: TextStyle(
                fontSize: 16,
              ),
            ))
        .toList();

    return SimpleDialog(
      titlePadding: EdgeInsets.all(0),
      contentPadding: EdgeInsets.all(0),
      children: <Widget>[
        new Container(
          decoration: new BoxDecoration(
            color: Colors.white,
          ),
          child: Image.file(image, fit: BoxFit.fitHeight),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: labelsList.isEmpty
              ? Center(child: Text("No matching labels"))
              : Column(children: labelsList),
        ),
        SimpleDialogOption(
          child: Center(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                    child: FlatButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: Text(
                    "CLOSE",
                    style: TextStyle(
                      color: Theme.of(context).accentColor,
                    ),
                  ),
                )),
                Expanded(
                  child: RaisedButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                    color: Theme.of(context).accentColor,
                    elevation: 4.0,
                    child: Text(
                      "RETAKE",
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ModelStatusInfo extends StatelessWidget {
  final Dataset dataset;
  final bool doesModelExist;
  final String modelStatus;

  const ModelStatusInfo({this.dataset, this.doesModelExist, this.modelStatus});

  @override
  Widget build(BuildContext context) {
    return new StreamBuilder(
        stream: Firestore.instance
            .collection("operations")
            .where("dataset_id", isEqualTo: dataset.automlId)
            .snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return const Text('Loading...');

          var statusText = modelStatus;
          var modelIcon = doesModelExist ? Icons.check : Icons.clear;

          if (snapshot.data.documents.isNotEmpty) {
            final pendingOps = snapshot.data.documents
                .where((document) => document["done"] == false);
            if (pendingOps.length > 0) {
              statusText = "Training under progress";
              modelIcon = Icons.cached;
            }
          }

          return new Row(
            children: <Widget>[
              Icon(modelIcon, size: 16),
              SizedBox(width: 4),
              new Text(
                statusText,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          );
        });
  }
}
