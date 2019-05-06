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

import * as sgMail from '@sendgrid/mail';
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
/** App for serving the API that interacts with AutoML API */
import { app } from './automlapi';

admin.initializeApp();
sgMail.setApiKey(functions.config().sendgrid.key);

/**
 * A function to check & update progress of a long running operations
 * in AutoML.
 */
export { checkOperationProgress } from './check_operations_progress';
/**
 * Clean up related metadata (labels, models, videos) from Firestore and storage
 * when a dataset is deleted, or when a label is deleted
 */
export { deleteDataset, deleteLabel } from './delete_dataset';
/**
 * Generates a label file for a dataset (provided as a query param)
 *
 * For more info on the format of the file refer to
 * https://cloud.google.com/vision/automl/alpha/docs/prepare#csv
 */
export { generateLabelFile } from './generate_label_file';
/**
 * A function to initiate all parts of training on automl.
 *
 * It listens for changes on operations collections and initiates subsequent
 * operations accordingly.
 */
export { manageTraining } from './manage_training';
/**
 * Deletes a collaborator's email from its parent dataset's field
 * when the collaborator is removed from the collaborators collection
 */
export { removeCollaborator } from './remove_collaborator';
/**
 * A function to send an email invite to any new collaborator
 * that's added to a dataset
 */
export { sendInvite } from './send_invite';
/**
 * A function to convert a video to a set of images.
 *
 * The filePath of a video when picked by this function is:
 * `datasets/{dataset_name}/{label}/{video_ts}.mp4`
 *
 * which should be uploaded to:
 * `gs://{AUTOML_BUCKET}/{dataset_name}/{label}/{video_ts}/`
 */
export { videoToImages } from './video_to_images';
/**
 * Functions to manage sample counts and clean up images when new
 * samples are deleted
 */
export { deleteImage } from './images_upload_delete';
/**
 * Cron-jobs for checking operations progress
 */
export {
  importDataProgressCron,
  exportModelProgressCron,
  trainModelProgressCron,
} from './operations_crons';

export const automlApi = functions.https.onRequest(app);
