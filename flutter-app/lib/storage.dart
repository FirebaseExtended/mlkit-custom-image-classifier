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

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Initializes a new storage client
Future<FirebaseStorage> initStorage(bucketName) async {
  return FirebaseStorage(storageBucket: bucketName);
}

/// Wraps the storage client in an inherited widget so that it can be used
/// downstream
class InheritedStorage extends InheritedWidget {
  final FirebaseStorage storage;
  final FirebaseStorage autoMlStorage;

  InheritedStorage({this.storage, this.autoMlStorage, Widget child})
      : super(child: child);

  @override
  bool updateShouldNotify(InheritedWidget oldWidget) => true;

  static InheritedStorage of(BuildContext context) =>
      context.inheritFromWidgetOfExactType(InheritedStorage);
}
