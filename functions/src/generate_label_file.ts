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
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as functions from 'firebase-functions';
import { PROJECT_ID, AUTOML_BUCKET } from './constants';

/**
 * Generates a label file for a dataset (provided as a query param)
 *
 * For more info on the format of the file refer to
 * https://cloud.google.com/vision/automl/alpha/docs/prepare#csv
 */
export const generateLabelFile = functions.https.onRequest(
  async (request, response) => {
    const dataset = request.query['dataset'];
    if (!dataset) {
      response.status(404).json({ error: 'Dataset not found' });
    }
    try {
      const labelsFile = await generateLabel(dataset);
      response.json({ success: `File uploaded to ${labelsFile}` });
    } catch (err) {
      response.status(500).json({ error: err.toString() });
    }
  }
);

/**
 * Reads all images from the AUTOML bucket for a dataset, and generates
 * a labels.csv file along side the images/ folder in the AutoML bucket
 *
 * The images are expected to be in
 *
 * `gs://{AUTOML_BUCKET}/datasets/{dataset}/{label}/{video_ts}`
 *
 * where {video_ts} is the timestamp of the video when it was uploaded from the
 * app.
 *
 * The generated labels file is placed in
 * `gs://{AUTOML_BUCKET}/{dataset}/labels.csv
 *
 * @param dataset - the display name of the dataset
 */
async function generateLabel(dataset: string): Promise<String> {
  const storage = new Storage({ projectId: PROJECT_ID });
  const prefix = `datasets/${dataset}`;

  // get all images in the dataset
  const [files] = await storage.bucket(AUTOML_BUCKET).getFiles({ prefix });

  const csvRows = files
    .map(file => getMetadata(file.name))
    .filter((metadata): metadata is ImageMetadata => metadata !== null)
    .map(({ label, fullPath }) => `gs://${AUTOML_BUCKET}/${fullPath},${label}`);

  console.log('Total rows in labels.csv:', csvRows.length);

  // No videos found, abort
  if (csvRows.length === 0) {
    throw new Error(`No videos found`);
  }

  // now that we have the contents of the file, we write this to storage
  const destination = `${dataset}/labels.csv`;
  const localFilePath = path.join(os.tmpdir(), 'tmp_labels.csv');

  return new Promise((resolve, reject) => {
    fs.writeFile(localFilePath, csvRows.join('\n'), async err => {
      if (err) {
        reject(err);
      }
      // upload the file adjacent to the images folder
      console.log('Uploading to', destination);
      await storage
        .bucket(AUTOML_BUCKET)
        .upload(localFilePath, { destination });
      // delete the file locally
      fs.unlinkSync(localFilePath);

      resolve(destination);
    });
  });
}

/**
 * Extracts metadata from an image path on GCS
 *
 * @param {*} fullPath of the image in the GCS bucket. This is of the
 * format: `datasets/{dataset}/{label}/{image_number}.jpg`
 */
function getMetadata(fullPath: string): ImageMetadata | null {
  const parts = fullPath.replace('datasets/', '').split(path.sep);
  if (parts.length < 3) {
    console.log('unable to split path:' + fullPath);
    return null;
  }
  const [dataset, label] = parts;
  return { dataset, label, fullPath };
}

/** Metadata for an image stored in GCS */
interface ImageMetadata {
  dataset: string; // the dataset to which the image belongs
  label: string; // the label under which the image is stored
  fullPath: string; // gcs path
}
