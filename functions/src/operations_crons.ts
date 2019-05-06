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
import * as got from 'got';
import { CHECK_OPERATIONS_URL } from './constants';

/**
 * Check progress for import data operations
 */
export const importDataProgressCron = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async () => {
    try {
      const response = await got(`${CHECK_OPERATIONS_URL}?type=IMPORT_DATA`);
      console.log('successful response', response.body);
    } catch (error) {
      console.error(error.response.body);
    }
  });

/**
 * Check progress for export model operations
 */
export const exportModelProgressCron = functions.pubsub
  .schedule('every 10 minutes')
  .onRun(async () => {
    try {
      const response = await got(`${CHECK_OPERATIONS_URL}?type=EXPORT_MODEL`);
      console.log('successful response', response.body);
    } catch (error) {
      console.error(error.response.body);
    }
  });

/**
 * Check progress for train model operations
 */
export const trainModelProgressCron = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async () => {
    try {
      const response = await got(`${CHECK_OPERATIONS_URL}?type=TRAIN_MODEL`);
      console.log('successful response', response.body);
    } catch (error) {
      console.error(error.response.body);
    }
  });
