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
import 'package:scoped_model/scoped_model.dart';
import 'package:transparent_image/transparent_image.dart';

import 'camera.dart';
import 'constants.dart';
import 'models.dart';
import 'user_model.dart';
import 'widgets/dismissible_warning.dart';

enum Actions {
  deleteLabel,
}

/// Widget for rendering the labels list screen
class ListLabelSamples extends StatelessWidget {
  final Dataset dataset;
  final String labelKey;
  final String labelName;

  const ListLabelSamples(this.dataset, this.labelKey, this.labelName);

  @override
  Widget build(BuildContext context) {
    return ScopedModelDescendant<UserModel>(builder: (context, _, model) {
      final isOwner = dataset.isOwner(model);

      return new Scaffold(
        appBar: new PreferredSize(
          child: new Hero(
            tag: AppBar,
            child: new AppBar(
              leading: const BackButton(),
              title: new Text('${labelName.toUpperCase()}'),
              actions: [
                if (isOwner)
                  IconButton(
                    icon: Icon(Icons.delete_forever),
                    onPressed: () {
                      Firestore.instance
                          .collection('labels')
                          .document(labelKey)
                          .delete();
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          preferredSize: new AppBar().preferredSize,
        ),
        floatingActionButton: model.isLoggedIn()
            ? Align(
                alignment: Alignment.bottomRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    new FloatingActionButton.extended(
                      icon: const Icon(Icons.add_a_photo),
                      heroTag: 1,
                      label: const Text('Add Images'),
                      onPressed: () async {
                        final c =
                            Camera(dataset, labelName, labelKey, model, false);
                        await c.init();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => c,
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                    ),
                    new FloatingActionButton.extended(
                      icon: const Icon(Icons.file_upload),
                      heroTag: 2,
                      label: const Text('Upload Images'),
                      onPressed: () async {
                        final c =
                            Camera(dataset, labelName, labelKey, model, true);
                        await c.init();
                        if (c.resultList != null && c.resultList.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => c,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              )
            : Container(),
        // body of the screen
        body: new StreamBuilder(
          stream: Firestore.instance
              .collection('images')
              .where("parent_key", isEqualTo: labelKey)
              .snapshots(),
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(50.0),
                      child: Text(
                        "No samples recorded.",
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }

                final warningWidgets = <Widget>[
                  DismissibleMessageWidget(msg: DATA_QUALITY_MESSAGE),
                ];

                final gridView = GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 4.0,
                    crossAxisSpacing: 4.0,
                  ),
                  itemCount: snapshot.data.documents.length,
                  itemBuilder: (context, i) {
                    final document = snapshot.data.documents[i];
                    final sample = Sample.fromDocument(document);
                    return new ImageEntry(
                      key: ValueKey(sample.gcsURI),
                      dataset: dataset,
                      sample: Sample.fromDocument(document),
                      userModel: model,
                      onDelete: () {
                        document.reference.delete();
                      },
                    );
                  },
                );

                return Column(
                    children: warningWidgets
                      ..add(new Expanded(child: gridView)));
            }
          },
        ),
      );
    });
  }
}

/// Widget for rendering a sample entry on this page
class ImageEntry extends StatelessWidget {
  final Sample sample;
  final Dataset dataset;
  final Function onDelete;
  final UserModel userModel;

  const ImageEntry({
    Key key,
    this.sample,
    this.onDelete,
    this.userModel,
    this.dataset,
  }) : super(key: key);

  bool canDeleteVideo() {
    // if the logged in user is owner of the dataset or the uploader of the sample
    return dataset.isOwner(userModel) || sample.isOwner(userModel);
  }

  String getUploader() {
    return sample.isOwner(userModel) ? "you" : sample.ownerEmail;
  }

  @override
  Widget build(BuildContext context) {
    return GridTile(
      footer: GridTileBar(
        trailing: canDeleteVideo()
            ? IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  onDelete();
                })
            : null,
        title: Text("Added by"),
        subtitle: Text(
          "${getUploader()}",
          style: TextStyle(fontSize: 10),
        ),
        backgroundColor: Colors.black45,
      ),
      child: GestureDetector(
        onLongPress: () {
          // for debugging
          Scaffold.of(context).showSnackBar(
              SnackBar(content: Text('image: ${sample.filename}')));
        },
        onTap: () {
          showDialog(
              context: context,
              builder: (BuildContext context) {
                return new ImageViewerDialog(sample.gcsURI);
              });
        },
        child: sample.gcsURI.isNotEmpty
            ? FadeInImage.memoryNetwork(
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: kTransparentImage,
                image: sample.gcsURI,
                fit: BoxFit.cover,
              )
            : Icon(Icons.image, size: 200, color: Colors.black12),
      ),
    );
  }
}

class ImageViewerDialog extends StatelessWidget {
  final String imageUrl;

  const ImageViewerDialog(this.imageUrl);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      titlePadding: EdgeInsets.all(0),
      backgroundColor: Colors.black,
      contentPadding: EdgeInsets.all(0),
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(color: Colors.black),
          child: imageUrl.isNotEmpty
              ? FadeInImage.memoryNetwork(
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: kTransparentImage,
                  image: imageUrl,
                  fit: BoxFit.fitWidth,
                )
              : const Icon(Icons.image, size: 200, color: Colors.black12),
        ),
      ],
    );
  }
}
