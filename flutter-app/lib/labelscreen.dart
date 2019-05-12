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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_dataset_label_screen.dart';
import 'automl_api.dart';
import 'collaborators_page.dart';
import 'constants.dart';
import 'label_samples_grid.dart';
import 'models.dart';
import 'operations_page.dart';
import 'service.dart';
import 'user_model.dart';
import 'widgets/dismissible_warning.dart';
import 'widgets/rotating_progress_icon.dart';

enum Actions {
  deleteDataset,
  viewCollaborators,
  changeVisiblity,
  copyGCSPath,
  trainModel,
  viewPastOperations,
  exportToFirebase,
}

Future deleteDatasetAsync(Dataset dataset) async {
  // Fire off a request to delete the dataset from AutoML first
  await AutoMLApi.deleteDataset(dataset.automlId);

  // then clear the firestore collection
  await Firestore.instance.collection("datasets").document(dataset.id).delete();

  // Fire off a request to delete the data from storage
  DatasetService.delete(dataset.name).then((result) {
    print("[Delete] delete response for ${dataset.name}: $result");
  });
  return Future.value(true);
}

/// Widget for rendering the labels list screen
class ListLabelsScreen extends StatefulWidget {
  final Dataset dataset;

  const ListLabelsScreen(this.dataset);

  @override
  _ListLabelsScreenState createState() => _ListLabelsScreenState();
}

class _ListLabelsScreenState extends State<ListLabelsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();

  showSnackBar(String text) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void initState() {
    super.initState();
    _firebaseMessaging.requestNotificationPermissions(
        const IosNotificationSettings(sound: true, badge: true, alert: true));
    _firebaseMessaging.onIosSettingsRegistered
        .listen((IosNotificationSettings settings) {
      print("Settings registered: $settings");
    });
  }

  ///
  /// Training the dataset comprises of a set of steps
  /// 1. Generate the labels.csv file
  /// 2. Import the data into AutoML
  /// 3. Initiate training the model
  /// 4. Export the model into GCS
  ///
  /// All of these (apart from 1) returns long-running operations from AutoML.
  ///
  Future<void> _initTraining(BuildContext context, int trainingBudget) async {
    final datasetName = widget.dataset.name.trim();
    showSnackBar("Attempting to initiate training");

    try {
      await AutoMLApi.generateLabels(datasetName);
      showSnackBar("Generated labels for " + datasetName);

      final importDatasetOperation =
          await AutoMLApi.importDataset(datasetName, widget.dataset.automlId);

      _scaffoldKey.currentState.showSnackBar(
          SnackBar(content: Text("Started importing dataset: $datasetName")));

      // Add this operation to Firestore
      Firestore.instance.collection('operations').add({
        "dataset_id": widget.dataset.automlId,
        "name": importDatasetOperation,
        "last_updated": DateTime.now().millisecondsSinceEpoch,
        "done": false,
        "training_budget": trainingBudget,
        "type": "IMPORT_DATA"
      }).whenComplete(() {
        print("Added operation: $importDatasetOperation to Firestore");
      });

      // set the token on dataset so that it can be notfied when training completes
      final token = await _firebaseMessaging.getToken();
      await Firestore.instance
          .collection('datasets')
          .document(widget.dataset.id)
          .setData({"token": token}, merge: true);
    } catch (err) {
      showSnackBar("Error while starting training");
      print("Error $err");
    }
  }

  onPopupMenuItemClicked(Actions action) async {
    switch (action) {
      case Actions.deleteDataset:
        showDialog<bool>(
            context: context,
            builder: (BuildContext context) =>
                DeleteDatasetAlertDialog(widget.dataset)).then((goBack) {
          if (goBack != null && goBack) Navigator.pop(context);
        });
        return;
      case Actions.viewCollaborators:
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => new CollaboratorsPage(widget.dataset)));
        return;
      case Actions.copyGCSPath:
        // copy the dataset's gcs path to clipboard
        final automlBucket = "$AUTOML_BUCKET/datasets/${widget.dataset.name}";
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return SimpleDialog(
                titlePadding: EdgeInsets.all(0),
                contentPadding: EdgeInsets.only(left: 12),
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          automlBucket,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.content_copy),
                        iconSize: 16,
                        color: Colors.deepPurpleAccent,
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: automlBucket));
                          showSnackBar("GCS path copied to clipboard");
                        },
                      )
                    ],
                  ),
                ],
              );
            });
        return;
      case Actions.exportToFirebase:
        try {
          // do something
          final datasetName = widget.dataset.name.trim();
          await AutoMLApi.generateLabels(datasetName);
          showSnackBar("Generated labels for " + datasetName);

          await AutoMLApi.importDataset(datasetName, widget.dataset.automlId);
          showDialog(
              context: context,
              builder: (BuildContext context) =>
                  ExportToFirebaseDialog(datasetName));
        } catch (err) {
          showSnackBar("Error while exporting dataset to firebase");
          print("Error $err");
        }
        return;
      case Actions.changeVisiblity:
        Firestore.instance
            .collection('datasets')
            .document(widget.dataset.id)
            .setData({"isPublic": !widget.dataset.isPublic},
                merge: true).whenComplete(() {
          Navigator.pop(context);
        });
        return;
      case Actions.trainModel:
        final trainingBudget = await showDialog<int>(
            context: context,
            builder: (BuildContext context) => TrainModelPricingDialog());
        if (trainingBudget > 0) {
          await _initTraining(context, trainingBudget);
          showDialog(
              context: context,
              builder: (BuildContext context) => TrainingConfirmationDialog());
        }
        return;
      case Actions.viewPastOperations:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OperationsPage(dataset: widget.dataset),
          ),
        );
    }
  }

  buildPopupMenu() {
    return PopupMenuButton<Actions>(
      onSelected: onPopupMenuItemClicked,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Actions>>[
            const PopupMenuItem(
              child: Text('Train model'),
              value: Actions.trainModel,
            ),
            const PopupMenuItem(
              child: Text('View Collaborators'),
              value: Actions.viewCollaborators,
            ),
            const PopupMenuItem(
              child: Text('View Past Operations'),
              value: Actions.viewPastOperations,
            ),
            PopupMenuItem(
              child: widget.dataset.isPublic
                  ? Text('Make private')
                  : Text('Make public'),
              value: Actions.changeVisiblity,
            ),
            const PopupMenuItem(
              child: Text('Export to Firebase'),
              value: Actions.exportToFirebase,
            ),
            const PopupMenuItem(
              child: Text('Show bucket path'),
              value: Actions.copyGCSPath,
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              child: Text('Delete Dataset'),
              value: Actions.deleteDataset,
            ),
          ],
    );
  }

  @override
  Widget build(BuildContext scaffoldContext) {
    return ScopedModelDescendant<UserModel>(builder: (context, _, model) {
      final isOwner = widget.dataset.isOwner(model);
      final isCollaborator = widget.dataset.isCollaborator(model);

      return new Scaffold(
        key: _scaffoldKey,
        appBar: new PreferredSize(
          child: new Hero(
            tag: AppBar,
            child: new AppBar(
              leading: const BackButton(),
              title: new Text('${widget.dataset.name.toUpperCase()}'),
              actions: <Widget>[
                IconButton(
                  icon: Icon(Icons.help_outline),
                  onPressed: () {
                    showDialog(
                        context: context,
                        builder: (BuildContext context) => LabelsHelpDialog());
                  },
                ),
                if (isOwner) buildPopupMenu(),
              ],
            ),
          ),
          preferredSize: new AppBar().preferredSize,
        ),
        floatingActionButton: isOwner
            ? new FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text("Add Label"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddDatasetLabelScreen(
                          DataKind.Label, widget.dataset.id, "", ""),
                    ),
                  );
                },
              )
            : Container(),
        // body of the screen
        body: new StreamBuilder(
          stream: Firestore.instance
              .collection('labels')
              .where("parent_key", isEqualTo: widget.dataset.id)
              .snapshots(),
          builder:
              (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
            if (!snapshot.hasData)
              return Center(
                child: new CircularProgressIndicator(),
              );

            if (snapshot.data.documents.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(50.0),
                  child: Text(
                    "No labels added.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            }

            // See if any label has less than 10 images
            final bool invalidLabels = snapshot.data.documents
                .map((document) => document["total_images"] as int)
                .any((imageCount) => imageCount < 10);

            final labelListView = new ListView(
                children: snapshot.data.documents
                    .map((document) => new Container(
                        decoration: new BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Colors.grey[300])),
                        ),
                        child: new LabelEntry(
                          dataset: widget.dataset,
                          labelKey: document.documentID,
                          labelName: document['name'],
                          totalImages: document['total_images'],
                        )))
                    .toList());

            final List<Widget> messages = [
              new OperationProgress(dataset: widget.dataset),
              if (invalidLabels)
                // If there are less than 10 images in the dataset, show a warning
                new DismissibleMessageWidget(
                  msg:
                      "At least 10 images per label are required to start training",
                  color: Colors.red[400],
                ),
            ];

            if (isOwner || isCollaborator) {
              return Column(
                  children: messages..add(new Expanded(child: labelListView)));
            }
            return labelListView;
          },
        ),
      );
    });
  }
}

class OperationProgress extends StatelessWidget {
  final Dataset dataset;

  const OperationProgress({this.dataset});

  @override
  Widget build(BuildContext context) {
    return new StreamBuilder(
        stream: Firestore.instance
            .collection('operations')
            .where('dataset_id', isEqualTo: dataset.automlId)
            .orderBy('last_updated', descending: true)
            .snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading operations'));
          }
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return Text('Loading..');
            default:
              final pendingOps = snapshot.data.documents
                  .where((document) => !document["done"])
                  .toList();

              // if there are no pending operations, return the timestamp
              // of the last model trained
              if (pendingOps.isEmpty) {
                // TODO: show last model trained info
                return Container();
              }
              return Container(
                color: Colors.grey[200],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          RotatingProgressIcon(),
                          SizedBox(width: 8),
                          Text("Model training in progress"),
                        ],
                      ),
                      FlatButton(
                        child: Text('Details'),
                        textColor: Colors.deepPurple,
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => OperationsPage(
                                        dataset: dataset,
                                      )));
                        },
                      ),
                    ],
                  ),
                ),
              );
          }
        });
  }
}

/// Widget for rendering a label entry
class LabelEntry extends StatelessWidget {
  final String labelKey;
  final String labelName;
  final int totalImages;
  final Dataset dataset;

  const LabelEntry({
    this.labelKey,
    this.labelName,
    this.totalImages,
    this.dataset,
  });

  @override
  Widget build(BuildContext context) {
    bool _canEdit(UserModel model) =>
        dataset.isCollaborator(model) || dataset.isOwner(model);

    return new ScopedModelDescendant<UserModel>(builder: (context, _, model) {
      return new ListTile(
        title: new Container(
          child: InkWell(
              // show label videos to only owners and collaborators
              onTap: _canEdit(model)
                  ? () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => new ListLabelSamples(
                                dataset,
                                labelKey,
                                labelName,
                              ),
                        ),
                      );
                    }
                  : null,
              child: new Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  new Text(labelName),
                  if (_canEdit(model))
                    new Row(
                      children: [
                        Chip(
                          avatar: CircleAvatar(
                            backgroundColor: Colors.grey.shade800,
                            child: Text('$totalImages'),
                          ),
                          label: Text(totalImages == 1 ? 'image' : 'images'),
                          backgroundColor: Colors.white24,
                        ),
                        const Icon(Icons.navigate_next),
                      ],
                    ),
                ],
              )),
        ),
      );
    });
  }
}

class TrainingConfirmationDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Training started"),
      content: const Text(
          "Training has been successfully started. You will be" +
              " notified when it completes"),
      actions: <Widget>[
        new FlatButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("OK"),
        )
      ],
    );
  }
}

/// Alert dialog that pops up when the user clicks on delete dataset button
class DeleteDatasetAlertDialog extends StatefulWidget {
  final Dataset dataset;

  const DeleteDatasetAlertDialog(this.dataset);

  @override
  _DeleteDatasetAlertDialogState createState() =>
      _DeleteDatasetAlertDialogState();
}

class _DeleteDatasetAlertDialogState extends State<DeleteDatasetAlertDialog> {
  var isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Delete dataset"),
      content: Text(
          "This will delete all dataset related information for ${widget.dataset.name} "
          "including images, labels and models. Are you "
          "sure you want to continue? You can't undo "
          "this action."),
      actions: <Widget>[
        new FlatButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("CANCEL"),
        ),
        isLoading
            ? CircularProgressIndicator()
            : new RaisedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                  });
                  deleteDatasetAsync(widget.dataset).whenComplete(() {
                    Navigator.pop(context, true);
                  });
                },
                elevation: 4,
                child: const Text(
                  "DELETE",
                  style: TextStyle(color: Colors.white),
                ),
              ),
      ],
    );
  }
}

class TrainModelPricingDialog extends StatefulWidget {
  @override
  _TrainModelPricingDialogState createState() =>
      _TrainModelPricingDialogState();
}

class _TrainModelPricingDialogState extends State<TrainModelPricingDialog> {
  var trainingBudget = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Model Training'),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text("Configure max training time"),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Slider(
                value: trainingBudget.toDouble(),
                max: 10.0,
                min: 1.0,
                divisions: 10,
                onChanged: (v) {
                  setState(() {
                    trainingBudget = v.round();
                  });
                }),
          ),
          Text(trainingBudget == 1 ? '1 hour' : '$trainingBudget hours'),
          SizedBox(height: 30),
          InkWell(
            onTap: () async {
              if (await canLaunch(FIREBASE_PRICING_PAGE)) {
                await launch(FIREBASE_PRICING_PAGE);
              }
            },
            child: Text.rich(
              TextSpan(
                text:
                    'Model training is billed by the number of training hours' +
                        ' consumed. Please see.',
                children: [
                  TextSpan(
                    text: " Firebase pricing page ",
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                  TextSpan(text: "for details")
                ],
                style: TextStyle(
                  color: Colors.black38,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        new FlatButton(
          onPressed: () {
            Navigator.of(context).pop(0);
          },
          child: const Text("CANCEL"),
        ),
        new RaisedButton(
          onPressed: () {
            Navigator.pop(context, trainingBudget);
          },
          elevation: 4,
          child: const Text(
            "CONTINUE",
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class ExportToFirebaseDialog extends StatelessWidget {
  final String datasetName;

  const ExportToFirebaseDialog(this.datasetName);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Export Started"),
      content: const Text(
          "Exporting dataset to Firebase. This might take a few minutes.\n\n" +
              "Once this completes, the dataset will be available in the Firebase console."),
      actions: <Widget>[
        new FlatButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("OK"),
        )
      ],
    );
  }
}

class LabelsHelpDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text("Labels"),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
              child: Text("This shows a list of the possible labels that a"
                  " model for this dataset can identify.")),
        ),
        SimpleDialogOption(
          child: FlatButton(
            child: Text("Ok"),
            textColor: Colors.deepPurple,
            onPressed: () {
              Navigator.pop(context, false);
            },
          ),
        )
      ],
    );
  }
}
