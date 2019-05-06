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

import { Storage, Bucket } from '@google-cloud/storage';
import * as functions from 'firebase-functions';
import * as path from 'path';
import * as mkdirp from 'mkdirp';
import * as ffmpeg from 'fluent-ffmpeg';
import * as ffmpeg_static from 'ffmpeg-static';
import * as os from 'os';
import * as fs from 'fs';
import * as rimraf from 'rimraf';
import * as admin from 'firebase-admin';
import { PROJECT_ID, AUTOML_BUCKET } from './constants';

interface VideoMetadata {
  uploader: string;
  dataset_parent_key: string;
  parent_key: string;
}

/**
 * A function to convert a video to a set of images.
 *
 * The filePath of a video when picked by this function is:
 * `gs://STORAGE_BUCKET/videos/{dataset_name}/{label}/{video_ts}.mp4`
 *
 * The images generated from that video is then uploaded to:
 * `gs://{AUTOML_BUCKET}/datasets/{dataset_name}/{label}/filename.jpg
 */
export const videoToImages = functions.storage
  .object()
  .onFinalize(async object => {
    const fileBucket = object.bucket;

    const filePath = object.name!;
    const fileName = path.basename(filePath);
    const videoMetadata = (object.metadata as unknown) as VideoMetadata;
    console.log('Video with metadata', videoMetadata);

    // Exit if this is triggered on a file that is not an image.
    if (!filePath.endsWith('mp4')) {
      console.log('Not a dataset video. Exiting...');
      return;
    }

    // Download video from bucket to tmpFilePath
    const bucket = new Storage({ projectId: PROJECT_ID }).bucket(fileBucket);
    const tempFilePath = path.join(os.tmpdir(), fileName);
    const videoFile = bucket.file(filePath);
    await videoFile.download({ destination: tempFilePath });
    console.log('File path', filePath);
    console.log('Video downloaded locally to', tempFilePath);

    // Generate images from the video
    const videoTitle = path
      .basename(filePath)
      .replace(path.extname(filePath), '');
    const imgOutputDir = path.join(os.tmpdir(), `images/${videoTitle}`);

    // create the folder for generating images if it doesn't exist,
    // so that ffmpeg doesn't fail
    if (!fs.existsSync(imgOutputDir)) {
      mkdirp.sync(imgOutputDir);
    }

    console.log(`Generating images in ${imgOutputDir}`);
    const command = ffmpeg(tempFilePath)
      .setFfmpegPath(ffmpeg_static.path)
      .outputOption('-vf fps=1')
      .output(`${imgOutputDir}/img-%4d.jpg`);

    // run the command
    await promisifyCommand(command);

    // log the number of images generated
    const files = fs.readdirSync(imgOutputDir);
    console.log(`Generated ${files.length} files for ${videoTitle}`);

    // construct upload destination
    const uploadDestination = buildUploadPath(filePath);
    console.log('Uploading images from video to ', uploadDestination);

    // upload generated images to gcs bucket
    // A service-account key is required for signing the URL.
    const keyFilename = path.join(__dirname, 'service-account-key.json');
    const autoMlBucket = new Storage({ keyFilename }).bucket(AUTOML_BUCKET);
    await uploadFolderToGCS(
      autoMlBucket,
      imgOutputDir,
      uploadDestination,
      videoMetadata,
      videoTitle
    );
    console.log('Upload completed.. Proceeding to deletion');

    // delete the video locally (& GCS) along with the files generated
    await videoFile.delete();
    fs.unlinkSync(tempFilePath);
    rimraf.sync(imgOutputDir);
    console.log('Conversion completed');
  });

/**
 * @param videoPath - videos/<dataset_name>/<dataset_label>/<video_ts>.mp4
 *
 * @returns path of the format: datasets/{dataset_name}/{label}
 */
function buildUploadPath(videoPath: string): string {
  const parts = videoPath.split(path.sep);
  if (parts.length < 4) {
    throw new Error('too few parts in path' + videoPath);
  }
  return path.join('datasets', parts[1] /** dataset */, parts[2] /** label */);
}

/**
 * Converts a ffmpeg command into a promise
 */
function promisifyCommand(command: ffmpeg.FfmpegCommand): Promise<any> {
  return new Promise((resolve, reject) => {
    command
      .on('end', resolve)
      .on('error', reject)
      .run();
  });
}

/**
 * Upload a local folder to a GCS bucket and updates firestore with the generated
 * images
 *
 * @param bucket Reference to the GCS bucket
 * @param localFolder Path to the local folder that needs to be uploaded
 * @param destination Location in the bucket where the contents of the folder
 *     should go
 * @param videoMetadata Metadata about the video uploaded
 * @param videoTitle Title of the video file for which images being uploaded
 */
async function uploadFolderToGCS(
  bucket: Bucket,
  localFolder: string,
  destination: string,
  videoMetadata: VideoMetadata,
  videoTitle: string
) {
  console.log(`Uploading to gs://${bucket.name}/${destination}`);
  const imagesCollectionRef = await admin.firestore().collection('images');

  const { uploader, dataset_parent_key, parent_key } = videoMetadata;
  const neverExpireTs = new Date(2050, 1, 1).getTime();

  const uploadFile = async (filename: string) => {
    try {
      const fileDest = path.join(
        destination,
        `${videoTitle}-${path.basename(filename)}`
      );

      // upload the file to storage
      await bucket.upload(filename, { destination: fileDest });

      // get a signed url
      const [signedUrl] = await bucket
        .file(fileDest)
        .getSignedUrl({ action: 'read', expires: neverExpireTs });

      // and add it in firestore
      await imagesCollectionRef.doc().set({
        type: 'TRAIN',
        filename: filename,
        parent_key: parent_key,
        uploader: uploader,
        dataset_parent_key: dataset_parent_key,
        gcsURI: signedUrl,
        uploadPath: fileDest,
      });
    } catch (err) {
      console.error(err);
    }
  };

  // Upload all the images in folder
  const uploadPromises = fs
    .readdirSync(localFolder)
    .map(file => uploadFile(path.join(localFolder, file)));

  await Promise.all(uploadPromises);

  // Update the total count in Firestore
  const labelSnapshot = await admin
    .firestore()
    .collection('labels')
    .doc(parent_key);

  return admin.firestore().runTransaction(transaction => {
    return transaction.get(labelSnapshot).then(labelRef => {
      const { total_images } = labelRef.data() as any;
      transaction.update(labelSnapshot, {
        total_images: total_images + uploadPromises.length,
      });
    });
  });
}
