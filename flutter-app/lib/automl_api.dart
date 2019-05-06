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
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'constants.dart';

/// Wrapper over the AutoML API exposed by our firebase function
class AutoMLApi {
  static const _AUTOMLAPI = "/automlApi";

  /// Creates a dataset with name `dataset` in AutoML.
  /// Returns the dataset ID if successful
  static Future<String> createDataset(String dataset) async {
    final response = await http.post(
        Uri.https(FUNCTIONS_URL, "$_AUTOMLAPI/datasets"),
        body: {"displayName": dataset});
    if (response.statusCode == 200) {
      final Map body = jsonDecode(response.body);
      print("Got reponse" + body.toString());
      return body["name"]
          .split("/")
          .last; // the list value in the name is the ID
    } else {
      throw Exception('Failed to create dataset. ' + response.body);
    }
  }

  /// Deletes a dataset with the provided automlId
  static Future<void> deleteDataset(String automlId) async {
    final response = await http
        .delete(Uri.https(FUNCTIONS_URL, "$_AUTOMLAPI/datasets/$automlId"));
    if (response.statusCode == 200) {
      return Future.value();
    } else {
      throw Exception("Error while deleting dataset: " + response.body);
    }
  }

  /// Generates a label file for a dataset. Returns a void Future to indicate
  /// success
  static Future<void> generateLabels(String datasetName) async {
    final response = await http.get(Uri.https(
        FUNCTIONS_URL, "/generateLabelFile", {"dataset": datasetName}));
    if (response.statusCode == 200) {
      return Future.value();
    } else {
      throw Exception("Error while generating label file: " + response.body);
    }
  }

  /// Starts a long running operation on AutoML to import the data for the dataset
  /// @param datasetName - name of the dataset
  /// @param automlId - automl ID of the dataset
  /// @returns the name of the operation e.g
  /// projects/1042742261124/locations/us-central1/operations/ICN4156965867930410106
  static Future<String> importDataset(
      String datasetName, String automlId) async {
    final response = await http.post(
      Uri.https(FUNCTIONS_URL, "$_AUTOMLAPI/import"),
      body: {
        "name": datasetName,
        "datasetId": automlId,
        "labels": "labels.csv"
      },
    );
    if (response.statusCode == 200) {
      final Map body = jsonDecode(response.body);
      print("Got response" + body.toString());
      return body["name"];
    } else {
      throw Exception(
          "Error while initiating importing the dataset: " + response.body);
    }
  }
}
