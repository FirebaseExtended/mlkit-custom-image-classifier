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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scoped_model/scoped_model.dart';

import 'user_model.dart';
import 'widgets/google_sign_in_btn.dart';

class SignInPage extends StatelessWidget {
  static const routeName = '/mydatasets';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScopedModelDescendant<UserModel>(
        builder: (context, _, model) {
          return Center(
            child: ZeroStateSignIn(model: model),
          );
        },
      ),
    );
  }
}

class ZeroStateSignIn extends StatelessWidget {
  final UserModel model;

  ZeroStateSignIn({Key key, this.model}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              "To add datasets, please sign in first",
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ),
          GoogleSignInButton(
            onPressed: () {
              model.beginSignIn().then((FirebaseUser user) {
                model.setLoggedInUser(user);
                Navigator.of(context).pop(true);
              }).catchError((e) => print(e));
            },
          ),
        ],
      ),
    );
  }
}
