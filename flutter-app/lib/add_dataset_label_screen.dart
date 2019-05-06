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
import 'package:flutter/material.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:url_launcher/url_launcher.dart';

import 'automl_api.dart';
import 'constants.dart';
import 'user_model.dart';

enum DataKind { Dataset, Label }

bool notNull(Object o) => o != null;

/// Screen for adding new entries (datasets & labels) to Firestore
class AddDatasetLabelScreen extends StatefulWidget {
  final DataKind entity; // collection this note belongs to
  final String
      parentKey; // if a label, the parentKey is the ID of the dataset that this label belongs to
  final String docID; // if provided, it's the docID of the label
  final String value; // if provided, it's the value of the label

  const AddDatasetLabelScreen(
      this.entity, this.parentKey, this.docID, this.value);

  @override
  State<StatefulWidget> createState() => new _AddDatasetLabelScreenState();
}

class _AddDatasetLabelScreenState extends State<AddDatasetLabelScreen> {
  @override
  Widget build(BuildContext context) {
    final title = widget.entity == DataKind.Dataset
        ? new Text("Add a new dataset")
        : new Text("Add a label");

    return Scaffold(
      appBar: AppBar(title: title),
      body: ScopedModelDescendant<UserModel>(
        builder: (context, _, model) {
          return widget.entity == DataKind.Dataset
              ? new AddDatasetForm(model)
              : new AddLabelForm(widget.parentKey, widget.docID, widget.value);
        },
      ),
    );
  }
}

class AddDatasetForm extends StatefulWidget {
  final UserModel userModel;

  const AddDatasetForm(this.userModel);

  @override
  _AddDatasetFormState createState() => _AddDatasetFormState();
}

class _AddDatasetFormState extends State<AddDatasetForm> {
  TextEditingController _titleController;
  TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();

  final datasetTitleRegex = new RegExp("^[a-zA-Z][a-zA-Z0-9_]{0,31}\$");

  var setPublic = false;
  var isLoading = false;

  @override
  void initState() {
    super.initState();

    _titleController = new TextEditingController(text: '');
    _descriptionController = new TextEditingController(text: '');
  }

  // adds a dataset to the firestore collection
  Future addDataset(String title, String description) async {
    if (!widget.userModel.isLoggedIn()) {
      return;
    }

    final datasetId = await AutoMLApi.createDataset(title);

    await Firestore.instance.collection('datasets').document().setData({
      'automlId': datasetId,
      'name': title,
      'description': description,
      'ownerId': widget.userModel.user.uid,
      'isPublic': setPublic,
      'collaborators': [],
    });
  }

  void _handleSwitchChange(bool value) {
    setState(() {
      setPublic = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(15.0),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value.isEmpty) {
                    return "Please enter a valid title";
                  }
                  if (!datasetTitleRegex.hasMatch(value)) {
                    return "Can only contain letters, numbers, and underscores";
                  }
                },
              ),
              Padding(padding: new EdgeInsets.all(5.0)),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: 'Description'),
                validator: (value) {
                  if (value.isEmpty) {
                    return 'Please enter a valid description';
                  }
                },
              ),
              Padding(padding: new EdgeInsets.all(5.0)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.public, color: Colors.black38),
                      SizedBox(width: 4),
                      const Text('Make dataset public?',
                          style:
                              TextStyle(fontSize: 16, color: Colors.black45)),
                    ],
                  ),
                  Switch(onChanged: _handleSwitchChange, value: setPublic)
                ],
              ),
              Padding(padding: new EdgeInsets.all(2.0)),
              isLoading
                  ? CircularProgressIndicator()
                  : RaisedButton(
                      child: Text('SAVE'),
                      shape: new RoundedRectangleBorder(
                        borderRadius: new BorderRadius.circular(8.0),
                      ),
                      color: Colors.deepPurple,
                      textColor: Colors.white,
                      elevation: 4,
                      onPressed: () async {
                        if (!_formKey.currentState.validate()) {
                          return;
                        }

                        setState(() {
                          isLoading = true;
                        });

                        try {
                          await addDataset(
                            _titleController.text.trim(),
                            _descriptionController.text.trim(),
                          );
                          Navigator.pop(context);
                        } catch (err) {
                          setState(() {
                            isLoading = false;
                          });

                          await showDialog(
                              context: context,
                              builder: (BuildContext context) =>
                                  ErrorDisplayDialog(err));
                        }
                      },
                    ),
              SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  if (await canLaunch(FIREBASE_PRICING_PAGE)) {
                    await launch(FIREBASE_PRICING_PAGE);
                  }
                },
                child: Text.rich(
                  TextSpan(
                    text:
                        "Your datasets incur Cloud Storage costs in your project. " +
                            "Please see the",
                    children: [
                      TextSpan(
                          text: " Firebase pricing page ",
                          style: TextStyle(color: Colors.blueAccent)),
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
        ),
      ),
    );
  }
}

class AddLabelForm extends StatefulWidget {
  final String parentKey;
  final String docID;
  final String value;

  const AddLabelForm(this.parentKey, this.docID, this.value);

  @override
  _AddLabelFormState createState() => _AddLabelFormState();
}

class _AddLabelFormState extends State<AddLabelForm> {
  TextEditingController _titleController;
  var disableSubmit = true;

  @override
  void initState() {
    super.initState();
    _titleController = new TextEditingController(text: widget.value);
    disableSubmit = widget.value.isEmpty;
  }

  // adds a label to a firestore document (if provided)
  void addLabel(String text, String parentKey, [String document]) {
    Firestore.instance
        .collection('labels')
        .document(document)
        .setData({'name': text, 'parent_key': parentKey, 'total_images': 0});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(15.0),
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            TextField(
              controller: _titleController,
              onChanged: (v) {
                setState(() {
                  disableSubmit = v.trim().isEmpty;
                });
              },
              decoration: InputDecoration(labelText: 'Title'),
            ),
            Padding(padding: new EdgeInsets.all(5.0)),
            RaisedButton(
              child: Text('SAVE'),
              color: Colors.deepPurpleAccent,
              textColor: Colors.white,
              elevation: 4,
              onPressed: disableSubmit
                  ? null
                  : () async {
                      if (widget.docID.length > 0) {
                        // already entry exists, add a new label
                        addLabel(
                          _titleController.text.trim(),
                          widget.parentKey,
                          widget.docID,
                        );
                      } else {
                        // create the first label
                        addLabel(
                          _titleController.text.trim(),
                          widget.parentKey,
                        );
                      }
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorDisplayDialog extends StatelessWidget {
  final Exception err;

  const ErrorDisplayDialog(this.err);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(
            Icons.warning,
            color: Colors.red,
          ),
          const SizedBox(width: 8),
          const Text(
            'ERROR',
            style: TextStyle(color: Colors.red),
          ),
        ],
      ),
      content: Text(err.toString()),
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
