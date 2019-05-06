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

import { Storage } from '@google-cloud/storage';
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { PROJECT_ID, AUTOML_BUCKET } from './constants';

/**
 * Clean up related metadata (labels, models, videos) from Firestore and storage
 * when a dataset is deleted
 */
export const deleteDataset = functions.firestore
  .document('datasets/{datasetId}')
  .onDelete(async (snap, context) => {
    const { datasetId } = context.params;
    const { name, automlId } = snap.data() as any;

    console.log(`Attempting to delete dataset: ${name} with id: ${datasetId}`);

    // delete the collaborators subcollection
    try {
      const query = admin
        .firestore()
        .collection('collaborators')
        .where('parent_key', '==', datasetId);
      await new Promise((resolve, reject) => {
        deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
      });
      console.log('Successfully deleted collaborators.');
    } catch (err) {
      console.error(`Error while deleting collaborators for dataset: ${name}`);
    }

    // delete all labels for this dataset
    try {
      const query = admin
        .firestore()
        .collection('labels')
        .where('parent_key', '==', datasetId);
      // TODO: Delete all videos from storage for each label

      // delete all videos first
      const labelsSnapshot = await query.get();
      labelsSnapshot.docs.forEach(async label => {
        try {
          await deleteImagesForLabels(label.id);
        } catch (err) {
          console.error(`Error in deleting videos for label: ${label.id}`);
        }
      });
      await new Promise((resolve, reject) => {
        deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
      });
      console.log('Successfully deleted labels.');
    } catch (err) {
      console.error(`Error while deleting labels for dataset: ${name}`);
    }

    // delete all the models from firestore
    try {
      const query = admin
        .firestore()
        .collection('models')
        .where('dataset_id', '==', automlId);
      await new Promise((resolve, reject) => {
        deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
      });
      // TODO: clear all data from storage for these models
      console.log('Successfully deleted models from firestore');
    } catch (err) {
      console.error(`Error while deleting models for dataset: ${name}`);
    }

    // delete all the operations from firestore
    try {
      const query = admin
        .firestore()
        .collection('operations')
        .where('dataset_id', '==', automlId);

      await new Promise((resolve, reject) => {
        deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
      });
    } catch (err) {
      console.error(`Error while deleting operations for dataset: ${name}`);
    }

    try {
      // delete all the files from automl bucket
      const autoMlBucket = new Storage({ projectId: PROJECT_ID }).bucket(
        AUTOML_BUCKET
      );
      const [files] = await autoMlBucket.getFiles({ prefix: name });
      files.forEach(async file => {
        await file.delete();
      });
      console.log('Deleted files from automl bucket for dataset', name);
    } catch (err) {
      console.error('Error deleting files from automl bucket for', name);
    }
  });

/**
 * Clean up images under a label when a label is deleted
 */
export const deleteLabel = functions.firestore
  .document('labels/{labelId}')
  .onDelete(async (snap, context) => {
    const { name } = snap.data() as any;
    const { labelId } = context.params;
    console.log(`Attempting to delete label: ${name}`);
    await deleteImagesForLabels(labelId);
  });

function deleteImagesForLabels(labelId: string) {
  const query = admin
    .firestore()
    .collection('images')
    .where('parent_key', '==', labelId);
  return new Promise((resolve, reject) => {
    deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
  });
}

function deleteQueryBatch(
  db: admin.firestore.Firestore,
  query: FirebaseFirestore.Query,
  batchSize: number,
  resolve: () => void,
  reject: () => void
) {
  query
    .get()
    .then(snapshot => {
      // When there are no documents left, we are done
      if (snapshot.size === 0) {
        return 0;
      }

      // Delete documents in a batch
      const batch = db.batch();
      snapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
      });

      return batch.commit().then(() => {
        return snapshot.size;
      });
    })
    .then(numDeleted => {
      if (numDeleted === 0) {
        resolve();
        return;
      }

      // Recurse on the next process tick, to avoid
      // exploding the stack.
      process.nextTick(() => {
        deleteQueryBatch(db, query, batchSize, resolve, reject);
      });
    })
    .catch(reject);
}
