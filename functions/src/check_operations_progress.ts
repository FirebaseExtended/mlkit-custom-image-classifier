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

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { Compute, JWT, UserRefreshClient, GoogleAuth } from "google-auth-library";
import {
  AUTOML_API_SCOPE,
  AUTOML_ROOT_URL,
  LOCATION,
  PROJECT_ID,
  AUTOML_API_URL,
  AUTOML_BUCKET_URL,
} from "./constants";
import { OperationMetadata } from "./types";
import DocumentSnapshot = FirebaseFirestore.DocumentSnapshot;

const automl = require('@google-cloud/automl');
const clientMl = new automl.v1beta1.AutoMlClient();
const parent = clientMl.locationPath(PROJECT_ID, LOCATION);

const auth = new GoogleAuth({
  scopes: 'https://www.googleapis.com/auth/cloud-platform'
});

type AuthClient = Compute | JWT | UserRefreshClient;

function isValidType(type: string): boolean {
  return (
    type === "IMPORT_DATA" || type === "EXPORT_MODEL" || type === "TRAIN_MODEL"
  );
}

/**
 * A function to check & update progress of a long running progression
 * in AutoML.
 */
export const checkOperationProgress = functions.https.onRequest(
  async (request, response) => {
    const operationType = request.query["type"];
    if (!operationType) {
      response.status(404).json({ error: "Operation `type` needed" });
      return;
    }
    if (!isValidType(operationType as string)) {
      response.status(400).json({
        error: "type should be one of IMPORT_DATA, EXPORT_MODEL, TRAIN_MODEL",
      });
      return;
    }
    try {
      // const snapshotToDeploy = await admin
      //   .firestore()
      //   .collection("operations")
      //   .where("type", "==", "TRAIN_MODEL")
      //   .where("done", "==", true)
      //   .where("deployed", "==", false)
      //   .get();
      // console.log(`data to train empty: ${snapshotToDeploy.empty}`);
      // if (!snapshotToDeploy.empty) {
      //   snapshotToDeploy.docs.forEach(async doc => {
      //     const docData = doc.data();
      //     await deployModel(docData["dataset_id"]);
      //     console.log(`Deployed, update state`);
      //     //update ref
      //     await doc.ref.set(
      //       {
      //         last_updated: Date.now(),
      //         deployed: true
      //       },
      //       { merge: true }
      //     );
      //   });
      // }

      // const client = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
      const client = await auth.getClient();

      const snapshot = await admin
        .firestore()
        .collection("operations")
        .where("type", "==", operationType)
        .where("done", "==", false)
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
      console.log("Deploy model with ml");


      response.status(200).json({
        success: `${snapshot.docs.length} operations updated: ${operationType}`,
      });
    } catch (err) {
      response.status(500).json({ error: err.json });
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
  const operationName = data["name"];
  console.log(`dataset: ${operationName}`);

  const resp = await queryOperationStatus(operationName, client);
  // const resp = await operationStatus(operationName);
  console.log(`update operation with: ${resp.done}`);
  await doc.ref.set(
    {
      last_updated: Date.now(),
      done: resp.done ? resp.done : false,
      deployed: data["deployed"] === undefined ? false : data["deployed"]
    },
    { merge: true }
  );

  console.log(resp.name); // Full model path
  console.log(resp.name.replace(/projects\/[a-zA-Z0-9-]*\/locations\/[a-zA-Z0-9-]*\/models\//, '')); // Just the model-id
}

async function queryOperationStatus(
  operationName: String,
  client: AuthClient
): Promise<OperationMetadata> {
  const url = `${AUTOML_ROOT_URL}/${operationName}`;
  const resp = await client.request({ url });
  return resp.data as OperationMetadata;
}

async function deployModel(modelId: String) {
  // Construct request
  const request = {
    name: clientMl.modelPath(PROJECT_ID, LOCATION, 'v20201209133002'),
  };

  const [operation] = await clientMl.deployModel(request);

  // Wait for operation to complete.
  const [response] = await operation.promise();
  console.log(`Model deployment finished. ${response}`);
}

async function logOperationInFirestore(
  datasetId: string,
  operationMetadata: OperationMetadata,
  type: string
) {
  return await admin
    .firestore()
    .collection("operations")
    .add({
      last_updated: Date.now(),
      type,
      done: false,
      dataset_id: datasetId,
      name: operationMetadata.name,
    });
}