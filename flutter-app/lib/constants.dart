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

// Minimum number of videos required for each label
const MIN_VIDEOS_PER_LABEL = 3;

// Minimum number of videos of training category required for each label
const MIN_TRAINING_VIDEOS_PER_LABEL = 1;

// Minimum number of videos of testing category required for each label
const MIN_TESTING_VIDEOS_PER_LABEL = 1;

// Minimum number of videos of validation category required for each label
const MIN_VALIDATION_VIDEOS_PER_LABEL = 1;

// Toggles where video type configuration (training/test/validation) is allowed
const SHOW_VIDEO_TYPE_TOGGLES = true;

// Path to the AutoML Bucket
// TODO: Needs to be configured as a part of onboarding
const PROJECT_ID = "";

// Firebase bucket for storage
const STORAGE_BUCKET = "gs://$PROJECT_ID.appspot.com";

// AutoML bucket
const AUTOML_BUCKET = "gs://$PROJECT_ID-vcm";

const DATA_QUALITY_MESSAGE =
    'Be sure to include a diverse set of at least 100 images for improved accuracy';

const FIREBASE_PRICING_PAGE = "https://firebase.google.com/pricing";

// URL for the functions hosted by this
const FUNCTIONS_URL = "us-central1-$PROJECT_ID.cloudfunctions.net";
