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
import * as path from 'path';
import fetch from 'node-fetch';
import * as luxon from 'luxon';
import { AUTOML_FUNCTIONS_BACKEND, AUTOML_BUCKET_URL } from './constants';
import { OperationMetadata } from './types';
import { Storage } from '@google-cloud/storage';

const IMPORT_DATA_OPERATION = 'IMPORT_DATA';
const TRAIN_MODEL_OPERATION = 'TRAIN_MODEL';
const EXPORT_MODEL_OPERATION = 'EXPORT_MODEL';
const MODEL_FILE_NAME = 'model.tflite';
const LABELS_FILE_NAME = 'dict.txt';
// Format from https://cloud.google.com/vision/automl/alpha/docs/reference/rest/v1beta1/projects.locations.models/export#modelexportoutputconfig
const MODEL_EXPORT_DATE_FORMAT = 'yyyy-MM-dd_HH-mm-ss-SSS';

/**
 * A function to initiate all parts of training on automl.
 *
 * It listens for changes on operations collections and initiates subsequent
 * operations accordingly.
 *
 * IMPORT_DATA -> TRAIN_MODEL -> EXPORT_MODEL
 */
export const manageTraining = functions.firestore
  .document('operations/{operationId}')
  .onUpdate(async (change, context) => {
    const { after, before } = change;
    console.log(`Operation updated: ${context.params.operationId}`);

    if (after === undefined || before === undefined) {
      console.log('One of after|before is undefined. Aborting...');
      return;
    }

    const { done: newDoneState } = after.data() as any;
    const {
      type,
      done: previousDoneState,
      dataset_id: datasetId,
      training_budget,
    } = before.data() as any;

    // If an IMPORT_DATA operation just went from done: false -> done: true
    // we initiate TRAIN_MODEL operation to create a new model.
    if (!previousDoneState && newDoneState && type === IMPORT_DATA_OPERATION) {
      console.log('Detected an IMPORT_DATA operation completion');

      // 1. trigger the next step, i.e TRAIN_MODEL
      console.log(
        `Attempting to initiate training for datasetId: ${datasetId}`
      );

      // call the functions autoML backend to initiate training
      const resp = await fetch(AUTOML_FUNCTIONS_BACKEND + '/train', {
        method: 'POST',
        body: JSON.stringify({
          datasetId: datasetId,
          trainBudget: training_budget === undefined ? 1 : training_budget,
        }),
        headers: { 'Content-Type': 'application/json' },
      });
      const json = await resp.json();
      console.log('Got operation response:', json);

      // 2. Add this in operations collection
      if (resp.status !== 200) {
        console.error('Error while initiating training the dataset', resp.body);
        return;
      }

      const operationMetadata = json as OperationMetadata;
      await logOperationInFirestore(
        datasetId,
        operationMetadata,
        TRAIN_MODEL_OPERATION
      );
      console.log('Saved operation in firestore');
    }

    // If a TRAIN_MODEL operation just went from done: false -> done: true,
    // we initiate EXPORT_MODEL operation for the latest model available
    if (!previousDoneState && newDoneState && type === TRAIN_MODEL_OPERATION) {
      console.log('Detected a TRAIN_MODEL operation completion.');

      // 1. trigger the next sep i.e. EXPORT_MODEL
      console.log(`Attempting to initiate export for datasetId: ${datasetId}`);

      // call the functions autoML backend to initiate export
      const gcsPath = `${AUTOML_BUCKET_URL}/models/on-device/${datasetId}`;
      console.log('Attempting to initiate export to gcs path', gcsPath);
      const resp = await fetch(
        AUTOML_FUNCTIONS_BACKEND + '/exportlatestmodel',
        {
          method: 'POST',
          body: JSON.stringify({ datasetId, gcsPath }),
          headers: { 'Content-Type': 'application/json' },
        }
      );
      if (resp.status !== 200) {
        console.error(`Error while exporting model`, resp.body);
        return;
      }
      const json = await resp.json();
      console.log('Got operation response:', json);

      // 2. Add this in operations collection
      if (resp.status !== 200) {
        console.error('Error while exporting the model for dataset', resp.body);
        return;
      }

      const operationMetadata = json as OperationMetadata;
      await logOperationInFirestore(
        datasetId,
        operationMetadata,
        EXPORT_MODEL_OPERATION
      );
      console.log('Saved operation in firestore');
    }

    // If an EXPORT_MODEL operationgg just went from done: false -> done: true
    // we write the file details of the latest export in firestore models
    if (!previousDoneState && newDoneState && type === EXPORT_MODEL_OPERATION) {
      console.log('Detected a EXPORT_MODEL operation completion');

      console.log('Attempting to find the path for the latest model generated');

      // Model files are stored in AUTOML_BUCKET/models/on-device/$dataset_id/$timestamp/

      // 1. List all the folders in the model export location
      const prefix = `models/on-device/${datasetId}/`;
      const [files] = await new Storage().bucket(AUTOML_BUCKET_URL).getFiles({
        prefix,
      });

      const allExports = Array.from(
        new Set(
          files
            .map(file => file.metadata.name)
            .map(file => file.split(path.sep)[3])
        )
      ); // [3] => folder name

      if (allExports.length === 0) {
        throw new Error('No exports found in ' + prefix);
      }

      // Sample folder generated by automl: 2019-03-19_21-30-02-757_tflite/
      const sanitizeFolderName = (s: string) => s.replace('_tflite', '');

      // 2. To get the latest folder, sort the folder names by converting them to dates
      const latestExportFolder = allExports.sort((a, b) => {
        const d1 = luxon.DateTime.fromFormat(
          sanitizeFolderName(a),
          MODEL_EXPORT_DATE_FORMAT
        );
        const d2 = luxon.DateTime.fromFormat(
          sanitizeFolderName(b),
          MODEL_EXPORT_DATE_FORMAT
        );
        if (!d1.isValid) {
          throw new Error('Unable to parse folder name: ' + a);
        }
        if (!d2.isValid) {
          throw new Error('Unable to parse folder name: ' + b);
        }
        return d2.toMillis() - d1.toMillis();
      })[0];

      const latestExportTs = luxon.DateTime.fromFormat(
        sanitizeFolderName(latestExportFolder),
        MODEL_EXPORT_DATE_FORMAT
      );

      console.log(
        'Latest export found: ',
        latestExportFolder,
        'for timestamp:',
        latestExportTs.toISO()
      );

      // 3. Narrow down the files in the latest exported folder
      const modelFiles = files
        .map(file => file.metadata.name)
        .filter(filename => filename.includes(latestExportFolder));

      // 4. Add a new document in firestore with references to dict.txt and model.tflite
      const labelsFile = getOnlyElement(
        modelFiles.filter(filename => filename.includes(LABELS_FILE_NAME))
      );
      const modelFile = getOnlyElement(
        modelFiles.filter(filename => filename.includes(MODEL_FILE_NAME))
      );
      console.log('Model file:', modelFile, '\nlabels file:', labelsFile);

      await admin
        .firestore()
        .collection('models')
        .add({
          dataset_id: datasetId,
          model: modelFile,
          label: labelsFile,
          generated_at: latestExportTs.toMillis(),
        });

      console.log('Saved model export info to firestore');

      // send a push notification to the owner
      await notifyOwner(datasetId);
    }
  });

async function notifyOwner(datasetId: string) {
  try {
    const snapshot = await admin
      .firestore()
      .collection('datasets')
      .where('automlId', '==', datasetId)
      .get();

    const document = getOnlyElement(snapshot.docs);
    const { token, name } = document.data() as any;
    await admin.messaging().sendToDevice(token, {
      notification: {
        title: 'Training Complete',
        body: `Dataset: ${name} has been trained successfully & can now be used for inference`,
      },
    });
    console.log('sent notification to admin for dataset: ', name);
  } catch (err) {
    console.error('Error sending push notification for dataset ', datasetId);
    console.error(err);
  }
}

function getOnlyElement<T>(arr: T[]): T {
  if (arr.length > 1) {
    throw new Error('Too many elements. Expected 1');
  }
  if (arr.length === 0) {
    throw new Error('Too few elements. Expected 1');
  }
  return arr[0];
}

async function logOperationInFirestore(
  datasetId: string,
  operationMetadata: OperationMetadata,
  type: string
) {
  return await admin
    .firestore()
    .collection('operations')
    .add({
      last_updated: Date.now(),
      type,
      done: false,
      dataset_id: datasetId,
      name: operationMetadata.name,
    });
}
