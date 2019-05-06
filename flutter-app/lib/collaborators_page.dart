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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'models.dart';

/// Page that allow admins to manage collaborators for their datasets
class CollaboratorsPage extends StatelessWidget {
  final Dataset dataset;

  const CollaboratorsPage(this.dataset);

  @override
  Widget build(BuildContext context) {
    final query = Firestore.instance
        .collection('collaborators')
        .where("parent_key", isEqualTo: dataset.id);

    return new Scaffold(
      appBar: new PreferredSize(
        child: new Hero(
          tag: AppBar,
          child: new AppBar(
            leading: const BackButton(),
            title: new Text('Collaborators'),
          ),
        ),
        preferredSize: new AppBar().preferredSize,
      ),
      floatingActionButton: new FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: new Icon(Icons.person_add),
        onPressed: () async {
          await showDialog(
              context: context,
              builder: (context) => InviteUserAlertDialog(dataset));
        },
      ),
      body: new StreamBuilder(
          stream: query.snapshots(),
          builder:
              (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
            if (snapshot.hasError) {
              return new Text('Error: ${snapshot.error}');
            }
            switch (snapshot.connectionState) {
              case ConnectionState.waiting:
                return Center(child: CircularProgressIndicator());
              default:
                if (snapshot.data.documents.isEmpty) {
                  return ZeroState(this.dataset.name);
                }

                final tiles =
                    snapshot.data.documents.map((DocumentSnapshot document) {
                  return Dismissible(
                    key: Key(document.documentID),
                    direction: DismissDirection.endToStart,
                    onDismissed: (direction) {
                      document.reference.delete();
                    },
                    background: Container(
                      color: Colors.red,
                      child: const ListTile(
                        trailing:
                            Icon(Icons.delete, color: Colors.white, size: 32),
                      ),
                    ),
                    child: new ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(document["email"]),
                      subtitle: Text("Invited on ${document["invitedAt"]}"),
                    ),
                  );
                });

                return ListView(
                    children:
                        ListTile.divideTiles(tiles: tiles, context: context)
                            .toList());
            }
          }),
    );
  }
}

/// Alert dialog for inviting collaborators to a dataset
class InviteUserAlertDialog extends StatefulWidget {
  final Dataset dataset;

  InviteUserAlertDialog(this.dataset);

  @override
  _InviteUserAlertDialogState createState() => _InviteUserAlertDialogState();
}

class _InviteUserAlertDialogState extends State<InviteUserAlertDialog> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  CollectionReference get collaborators =>
      Firestore.instance.collection('collaborators');

  DocumentReference get datasetRef =>
      Firestore.instance.collection('datasets').document(widget.dataset.id);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Invite users to collaborate"),
      content: Container(
        height: 100,
        child: Column(
          children: <Widget>[
            TextField(
              controller: _emailController,
              decoration: InputDecoration(hintText: 'Enter an email'),
            ),
            SizedBox(height: 12),
            Text(
                "This will allow user to add videos to existing labels in this dataset."),
          ],
        ),
      ),
      actions: <Widget>[
        new FlatButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: new Text("CANCEL"),
        ),
        new FlatButton(
          color: Colors.deepPurple,
          textColor: Colors.white,
          child: new Text("INVITE"),
          onPressed: () async {
            final emailId = _emailController.text;
            // TODO: Add better validation
            if (emailId.isNotEmpty) {
              await collaborators.add({
                'parent_key': widget.dataset.id,
                'email': emailId,
                'invitedAt': DateTime.now().toIso8601String(),
              });

              await datasetRef.setData({
                "collaborators": FieldValue.arrayUnion([emailId]),
              }, merge: true);
            }

            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

/// Zero state for collaborators page
class ZeroState extends StatelessWidget {
  final String datasetName;

  const ZeroState(this.datasetName);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Add collaborators for $datasetName.',
            style: TextStyle(fontSize: 18),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Great models need great datasets. Add collaborators that can help you add data'
              ' to this dataset.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
