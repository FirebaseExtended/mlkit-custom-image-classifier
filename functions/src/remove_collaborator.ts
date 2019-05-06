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
import { FieldValue } from '@google-cloud/firestore';

/**
 * Deletes a collaborator's email from its parent dataset's field
 * when the collaborator is removed from the collaborators collection
 */
export const removeCollaborator = functions.firestore
  .document('collaborators/{collaboratorId}')
  .onDelete(async (snap, context) => {
    const { email, parent_key: datasetKey } = snap.data() as any;

    console.log(
      `Attempting to remove ${email} from dataset with key: ${datasetKey}`
    );
    try {
      const datasetRef = admin
        .firestore()
        .collection('datasets')
        .doc(datasetKey);
      await datasetRef.update({ collaborators: FieldValue.arrayRemove(email) });
    } catch (err) {
      console.error(
        `Error while removing collaborator from dataset: ${datasetKey}`,
        err
      );
    }
  });
