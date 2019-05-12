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
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_dataset_label_screen.dart';
import 'constants.dart';
import 'datasets_list.dart';
import 'intro_tutorial.dart';
import 'signin_page.dart';
import 'storage.dart';
import 'user_model.dart';

void main() async {
  final FirebaseStorage storage = await initStorage(STORAGE_BUCKET);
  final FirebaseStorage autoMlStorage = await initStorage(AUTOML_BUCKET);
  runApp(new MyApp(
    storage: storage,
    autoMlStorage: autoMlStorage,
    userModel: UserModel(),
  ));
}

enum MainAction { logout, viewTutorial }

class MyApp extends StatelessWidget {
  final FirebaseStorage storage;
  final FirebaseStorage autoMlStorage;
  final UserModel userModel;

  const MyApp({
    Key key,
    @required this.storage,
    @required this.autoMlStorage,
    @required this.userModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ScopedModel<UserModel>(
      model: userModel,
      child: new InheritedStorage(
        storage: storage,
        autoMlStorage: autoMlStorage,
        child: new MaterialApp(
          title: 'Custom Image Classifier',
          theme: new ThemeData(
            primarySwatch: Colors.deepPurple,
            dividerColor: Colors.black12,
          ),
          initialRoute: MyHomePage.routeName,
          routes: {
            MyHomePage.routeName: (context) => MyHomePage(),
            IntroTutorial.routeName: (context) => IntroTutorial(),
          },
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  static const routeName = '/';

  const MyHomePage();

  @override
  _MyHomePageState createState() => new _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    checkAndShowTutorial();
  }

  void checkAndShowTutorial() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final seenTutorial = prefs.getBool('seenTutorial') ?? false;
    if (!seenTutorial) {
      Navigator.pushNamed(context, IntroTutorial.routeName);
    } else {
      print("Has seen tutorial before. Skipping");
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ScopedModel.of<UserModel>(context, rebuildOnChange: true);
    final query = Firestore.instance.collection('datasets');

    return new Scaffold(
      key: _scaffoldKey,
      appBar: new AppBar(
        title: new Text("Datasets"),
        actions: <Widget>[
          if (!model.isLoggedIn())
            IconButton(
              onPressed: () {
                model
                    .beginSignIn()
                    .then((user) => model.setLoggedInUser(user))
                    .catchError((e) => print(e));
              },
              icon: Icon(
                Icons.person_outline,
              ),
            ),
          model.isLoggedIn()
              ? PopupMenuButton<MainAction>(
                  onSelected: (MainAction action) {
                    switch (action) {
                      case MainAction.logout:
                        model.logOut();
                        break;
                      case MainAction.viewTutorial:
                        Navigator.pushNamed(context, IntroTutorial.routeName);
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuItem<MainAction>>[
                        PopupMenuItem<MainAction>(
                          child: Text.rich(
                            TextSpan(
                              text: 'Logout',
                              children: [
                                TextSpan(
                                  text: " (${model.user.displayName})",
                                  style: TextStyle(
                                    color: Colors.black38,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              ],
                            ),
                          ),
                          value: MainAction.logout,
                        ),
                        const PopupMenuItem<MainAction>(
                          child: Text('View Tutorial'),
                          value: MainAction.viewTutorial,
                        )
                      ],
                )
              : Container()
        ],
      ),
      body: DatasetsList(
        scaffoldKey: _scaffoldKey,
        query: model.isLoggedIn()
            ? query
            : query.where('isPublic', isEqualTo: true),
        model: model,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // show fab button only on personal datasets page
      floatingActionButton: new FloatingActionButton.extended(
        icon: Icon(Icons.add),
        label: Text("New Dataset"),
        onPressed: () async {
          if (model.isLoggedIn()) {
            Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AddDatasetLabelScreen(DataKind.Dataset, "", "", ""),
                ));
          } else {
            // Route to login page
            final result = await Navigator.push(
                context, MaterialPageRoute(builder: (context) => SignInPage()));
            if (result) {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          AddDatasetLabelScreen(DataKind.Dataset, "", "", "")));
            }
          }
        },
      ),
    );
  }
}
