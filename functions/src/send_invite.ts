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
import { FROM_EMAIL, APP_NAME } from './constants';

/**
 * A function to send an email invite to any new collaborator
 * that's added to a dataset
 */
export const sendInvite = functions.firestore
  .document('collaborators/{collaboratorId}')
  .onCreate(async (change, context) => {
    const { email, parent_key: datasetId } = change.data() as any;
    const datasetSnapshot = await admin
      .firestore()
      .collection('datasets')
      .doc(datasetId)
      .get();

    const { name: datasetName } = datasetSnapshot.data() as any;

    const msg = {
      to: email,
      from: FROM_EMAIL,
      subject: `You've been invited to ${APP_NAME}!`,
      text: `You've been invited to collaborate on a dataset on ${APP_NAME}!`,
      html:
        `You've been invited to collaborate on the <strong>${datasetName}</strong> dataset` +
        ` on ${APP_NAME}. Open the app and login to access the dataset.`,
    };

    try {
      await sgMail.send(msg);
      console.log(`Sent invite to user: ${email} for dataset: ${datasetName}`);
    } catch (err) {
      console.error('Unable to send email');
      console.error(err);
    }
  });
