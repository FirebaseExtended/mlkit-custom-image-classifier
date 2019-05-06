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

import * as admin from 'firebase-admin';
import { Storage } from '@google-cloud/storage';
import * as functions from 'firebase-functions';
import { AUTOML_BUCKET, PROJECT_ID } from './constants';

/**
 * Functions to manage sample counts and clean up images when new
 * samples are deleted
 */
export const deleteImage = functions.firestore
  .document('images/{imageId}')
  .onDelete(async change => {
    // 1. Decrement the total images count in label
    const { parent_key, uploadPath } = change.data() as any;

    const labelSnapshot = await admin
      .firestore()
      .collection('labels')
      .doc(parent_key);

    await admin.firestore().runTransaction(transaction => {
      return transaction.get(labelSnapshot).then(labelRef => {
        if (labelRef.exists) {
          const { total_images } = labelRef.data() as any;
          transaction.update(labelSnapshot, {
            total_images: Math.max(total_images - 1, 0),
          });
        }
      });
    });

    if (!uploadPath) {
      return;
    }

    const storage = new Storage({ projectId: PROJECT_ID });
    await storage
      .bucket(AUTOML_BUCKET)
      .file(uploadPath)
      .delete();

    console.log(`gs://${AUTOML_BUCKET}/${uploadPath} deleted.`);
  });
