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

// Firebase / GCP project ID
export const PROJECT_ID = process.env.GCLOUD_PROJECT;

// The name of the app
export const APP_NAME = "Custom Image Classifier";

// AutoML bucket name
export const AUTOML_BUCKET = `${PROJECT_ID}-vcm`;

// Location for the project
export const LOCATION = "us-central1";

// AutoML bucket path
export const AUTOML_BUCKET_URL = `gs://${PROJECT_ID}-vcm`;//testproject-afd2f.appspot.com
//export const AUTOML_BUCKET_URL = `gs://${PROJECT_ID}.appspot.com/vcm`;

export const AUTOML_API_SCOPE =
  "https://www.googleapis.com/auth/cloud-platform";

export const AUTOML_API_URL = `https://eu-automl.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}`;

export const AUTOML_ROOT_URL = "https://eu-automl.googleapis.com/v1beta1";

// TODO: Set this as a part of onboarding
export const FROM_EMAIL = "emigrantdd@gmail.com";

// URL for the Firebase function that serves the AutoML API
export const AUTOML_FUNCTIONS_BACKEND = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/automlApi`;

// URL for the Firebase function that checks operations progress
export const CHECK_OPERATIONS_URL = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/checkOperationProgress`;
