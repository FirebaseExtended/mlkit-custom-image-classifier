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

import 'user_model.dart';

/// Wrapper object over some file metadata that is downloaded
class DownloadedModelInfo {
  final String path;
  final int fileSizeInBytes;

  const DownloadedModelInfo(this.path, this.fileSizeInBytes);
}

/// Wrapper object over inference data returned from tflite
class Inference {
  final String label;
  final int index;
  final double confidence;

  const Inference({this.label, this.index, this.confidence});

  @override
  String toString() {
    return "Label: $label";
  }

  static Inference fromTfInference(Map inferenceResult) {
    if (inferenceResult.containsKey("label") &&
        inferenceResult.containsKey("confidence")) {
      return Inference(
        label: inferenceResult["label"],
        confidence: inferenceResult["confidence"],
      );
    }
    print("Unable to parse inference" + inferenceResult.toString());
    return null;
  }
}

/// Wrapper object over a dataset stored in Firestore
class Dataset {
  final String id; // key in firestore
  final String name;
  final bool isPublic;
  final String ownerId;
  final String description;
  final String automlId;
  final List<dynamic> collaborators;

  const Dataset(
      {this.id,
      this.name,
      this.isPublic,
      this.description,
      this.ownerId,
      this.collaborators,
      this.automlId});

  static Dataset fromDocument(DocumentSnapshot document) {
    return Dataset(
      id: document.documentID,
      name: document["name"],
      description: document["description"],
      isPublic: document["isPublic"] == true,
      ownerId: document["ownerId"],
      automlId: document["automlId"],
      collaborators: document["collaborators"].map((x) => x as String).toList(),
    );
  }

  bool isOwner(UserModel userModel) {
    return userModel.isLoggedIn() && ownerId == userModel.user.uid;
  }

  bool isCollaborator(UserModel userModel) {
    return userModel.isLoggedIn() &&
        collaborators.contains(userModel.user.email);
  }
}

enum SampleType {
  TRAIN,
  TEST,
  VALIDATION,
}

SampleType fromStr(String s) {
  if (s == "TRAIN") {
    return SampleType.TRAIN;
  }
  if (s == "TEST") {
    return SampleType.TEST;
  }
  if (s == "VALIDATION") {
    return SampleType.VALIDATION;
  }

  throw Exception('Cannot convert $s to VideoType');
}

String toString(SampleType videoType) {
  switch (videoType) {
    case SampleType.TRAIN:
      return "TRAIN";
    case SampleType.TEST:
      return "TEST";
    case SampleType.VALIDATION:
      return "VALIDATION";
  }
  throw Exception("Invalid video type");
}

/// Wrapper object over a sample (img) stored in Firestore
class Sample {
  final String id;
  final String gcsURI;
  final SampleType type;
  final String filename;
  final String ownerEmail;
  final String thumbnailUri;

  const Sample(
      {this.id,
      this.gcsURI,
      this.filename,
      this.type,
      this.ownerEmail,
      this.thumbnailUri});

  static Sample fromDocument(DocumentSnapshot document) {
    return Sample(
        id: document.documentID,
        filename: document['filename'],
        gcsURI: document['gcsURI'],
        type: fromStr(document["type"]),
        ownerEmail: document["uploader"],
        thumbnailUri: document["thumbnailUri"]);
  }

  bool isOwner(UserModel userModel) {
    return userModel.user.email == this.ownerEmail;
  }
}
