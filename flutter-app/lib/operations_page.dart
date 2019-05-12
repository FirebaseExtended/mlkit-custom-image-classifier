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
import 'widgets/rotating_progress_icon.dart';

class OperationsPage extends StatelessWidget {
  final Dataset dataset;

  const OperationsPage({this.dataset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Operations"),
      ),
      body: new OperationsList(dataset: dataset),
    );
  }
}

class OperationsList extends StatelessWidget {
  final Dataset dataset;

  const OperationsList({Key key, this.dataset}) : super(key: key);

  /// returns whether the date is today
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return now.day == date.day &&
        now.year == date.year &&
        now.month == date.month;
  }

  /// Convert the date to a timestamp
  String _toDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final minute = date.minute.toString().padLeft(2, '0');
    final time = "${date.hour}:$minute";
    return _isToday(date)
        ? time
        : "${date.year}/${date.month}/${date.day} $time";
  }

  ListTile _toListTile(DocumentSnapshot document) {
    return ListTile(
      key: Key(document.documentID),
      title: Text(document["type"]),
      leading: document["done"]
          ? Icon(Icons.check_circle, color: Colors.lightGreen)
          : RotatingProgressIcon(),
      subtitle: Text("Last updated: ${_toDate(document["last_updated"])}"),
    );
  }

  ListTile header(String text) => ListTile(
      key: Key(text),
      title: Text(text.toUpperCase(),
          style: TextStyle(fontSize: 16, color: Colors.black54)));

  @override
  Widget build(BuildContext context) {
    return new StreamBuilder(
        stream: Firestore.instance
            .collection('operations')
            .orderBy('last_updated', descending: true)
            .snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading operations'));
          }
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return Center(child: CircularProgressIndicator());
            default:
              if (snapshot.data.documents.isEmpty) {
                return Center(child: Text('No pending operations'));
              }
              final datasetOperations = snapshot.data.documents.where(
                  (document) => document["dataset_id"] == dataset.automlId);

              final pendingOps = datasetOperations
                  .where((document) => !document["done"])
                  .map(_toListTile);

              final completedOps = datasetOperations
                  .where((document) => document["done"])
                  .map(_toListTile);

              return ListView(
                children: [
                  if (pendingOps.isNotEmpty) header("in progress"),
                  if (pendingOps.isNotEmpty) ...pendingOps,
                  if (completedOps.isNotEmpty) header("completed"),
                  if (completedOps.isNotEmpty) ...completedOps,
                ],
              );
          }
        });
  }
}
