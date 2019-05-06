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

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { auth, Compute, JWT, UserRefreshClient } from 'google-auth-library';
import { AUTOML_API_SCOPE, AUTOML_ROOT_URL } from './constants';
import { OperationMetadata } from './types';
import DocumentSnapshot = FirebaseFirestore.DocumentSnapshot;

type AuthClient = Compute | JWT | UserRefreshClient;

function isValidType(type: string): boolean {
  return (
    type === 'IMPORT_DATA' || type === 'EXPORT_MODEL' || type === 'TRAIN_MODEL'
  );
}

/**
 * A function to check & update progress of a long running progression
 * in AutoML.
 */
export const checkOperationProgress = functions.https.onRequest(
  async (request, response) => {
    const operationType = request.query['type'];
    if (!operationType) {
      response.status(404).json({ error: 'Operation `type` needed' });
      return;
    }
    if (!isValidType(operationType)) {
      response.status(400).json({
        error: 'type should be one of IMPORT_DATA, EXPORT_MODEL, TRAIN_MODEL',
      });
      return;
    }
    try {
      const client = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });

      const snapshot = await admin
        .firestore()
        .collection('operations')
        .where('type', '==', operationType)
        .where('done', '==', false)
        .get();

      if (snapshot.empty) {
        response.status(200).json({
          success: `No pending operations found for type ${operationType}`,
        });
        return;
      }

      // for each operation, check the status
      snapshot.docs.forEach(async doc => {
        await updateOperation(doc, client);
      });

      response.status(200).json({
        success: `${snapshot.docs.length} operations updated: ${operationType}`,
      });
    } catch (err) {
      response.status(500).json({ error: err.toJSON() });
    }
  }
);

/**
 * curl
 -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
 -H "Content-Type: application/json" \
 https://automl.googleapis.com/v1beta1/projects/1042742261124/locations/us-central1/operations/ICN4381834005401348320
 {
  "name": "projects/1042742261124/locations/us-central1/operations/ICN4381834005401348320",
  "metadata": {
    "@type": "type.googleapis.com/google.cloud.automl.v1beta1.OperationMetadata",
    "createTime": "2019-03-03T16:14:37.524989Z",
    "updateTime": "2019-03-03T16:14:37.525009Z",
    "importDataDetails": {}
  }
}
 */
async function updateOperation(doc: DocumentSnapshot, client: AuthClient) {
  const data = doc.data();
  if (data === undefined) {
    return;
  }
  const operationName = data['name'];
  const resp = await queryOperationStatus(operationName, client);
  await doc.ref.set(
    {
      last_updated: Date.now(),
      done: resp.done ? resp.done : false,
    },
    { merge: true }
  );
}

async function queryOperationStatus(
  operationName: String,
  client: AuthClient
): Promise<OperationMetadata> {
  const url = `${AUTOML_ROOT_URL}/${operationName}`;
  const resp = await client.request({ url });
  return resp.data as OperationMetadata;
}
