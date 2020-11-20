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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:scoped_model/scoped_model.dart';

class UserModel extends Model {
  AuthResult _user;

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static UserModel of(BuildContext context) =>
      ScopedModel.of<UserModel>(context);

  bool isLoggedIn() => _user != null;

  UserModel() {
    attemptSilentSignIn();
  }

  void logOut() async {
    if (this.isLoggedIn()) {
      await _googleSignIn.signOut();
      await _auth.signOut();
      _user = null;
      notifyListeners();
    }
  }

  void attemptSilentSignIn() async {
    print("Attempting silent sign in");
    GoogleSignInAccount googleUser = await _googleSignIn.signInSilently();
    if (googleUser != null) {
      AuthResult user = await completeSignIn(googleUser);
      setLoggedInUser(user);
    }
  }

  void setLoggedInUser(AuthResult user) async {
    _user = user;
    notifyListeners();
  }

  Future<AuthResult> completeSignIn(GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.getCredential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    AuthResult user = await _auth.signInWithCredential(credential);
    print(
        "signed in ${user.user.displayName} with id: ${user.user.displayName}");
    return user;
  }

  /// begins the sign in flow
  Future<AuthResult> beginSignIn() async {
    GoogleSignInAccount googleUser = await _googleSignIn.signIn();
    return completeSignIn(googleUser);
  }

  AuthResult get user => _user;
}
