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

import 'package:http/http.dart' as http;

/// Common operations over backend dataset service
class DatasetService {
  static const _BACKEND_URL = "35.192.148.181";

  static Future<String> delete(String dataset) async {
    final response = await http.get(Uri.http(_BACKEND_URL, "/dataset/delete", {
      "dataset": dataset,
    }));
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to do training: ' + response.body);
    }
  }

  static Future<String> train(String dataset) async {
    final response = await http.get(Uri.http(_BACKEND_URL, "/train", {
      "dataset": dataset,
    }));
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to do training: ' + response.body);
    }
  }
}
