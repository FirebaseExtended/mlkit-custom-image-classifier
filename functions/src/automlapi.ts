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

import automl from '@google-cloud/automl';
import * as dayjs from 'dayjs';
import * as express from 'express';
import { auth } from 'google-auth-library';
import * as morgan from 'morgan';
import {
  AUTOML_API_SCOPE,
  AUTOML_API_URL,
  AUTOML_BUCKET_URL,
  LOCATION,
  PROJECT_ID,
} from './constants';
import { OperationMetadata } from './types';

export const app = express();
app.use(express.json());
app.use(morgan('combined'));

const client = new automl.v1beta1.AutoMlClient();

// Controls model type. For more options, see:
// https://cloud.google.com/vision/automl/alpha/docs/reference/rest/v1beta1/projects.locations.models#imageclassificationmodelmetadata
const DEFAULT_MODEL_TYPE = 'mobile-high-accuracy-1';

const DEFAULT_TRAIN_BUDGET = 1;
const DATASET_NAME_REGEX = new RegExp('^[a-zA-Z_0-9]+$');
const MODEL_VERSION_FORMAT = 'vYYYYMMDDHHmmss';
const parent = client.locationPath(PROJECT_ID, LOCATION);

// A model as returned by AutoML /models response
interface Model {
  name: string;
  datasetId: string;
  displayName: string;
  createTime: string;
  updateTime: string;
  imageClassificationModelMetadata: {
    trainBudget: string;
    trainCost: string;
    stopReason: string;
    modelType: string;
  };
}

interface ModelResp {
  model: Model[];
}

/// create a new dataset
function createDataset(displayName: String): Promise<any> {
  const dataset = {
    name: displayName,
    displayName,
    imageClassificationDatasetMetadata: {
      classificationType: 'MULTICLASS',
    },
  };

  return client.createDataset({ parent, dataset });
}

const extractIdFromName = (datasetName: string): string => {
  const parts = datasetName.split('/');
  return parts[parts.length - 1];
};

/// returns the ID of a dataset of the format ICN** or null if not found
function getDatasetName(automlId: string): Promise<string | null> {
  return client.listDatasets({ parent }).then((responses: any[]) => {
    const datasets = responses[0];
    for (const dataset of datasets) {
      if (extractIdFromName(dataset['name']) === automlId) {
        return dataset['name'];
      }
    }
    return null;
  });
}

/// initiates an operation on automl to start importing data for a dataset
async function importDataset(
  name: string,
  displayName: string,
  labels: string
): Promise<OperationMetadata> {
  const inputConfig = {
    gcsSource: {
      inputUris: [`${AUTOML_BUCKET_URL}/${displayName}/${labels}`],
    },
  };
  return client
    .importData({ name, inputConfig })
    .then((responses: any[]) => responses[1]); // initial api response with operation metadata
}

/**
 * List all datasets
 */
app.get('/datasets', async (req, res, next) => {
  try {
    const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
    const url = `${AUTOML_API_URL}/datasets`;
    const resp = await authClient.request({ url });
    res.json(resp.data);
  } catch (err) {
    console.error(err);
    next(err);
  }
});

/**
 * Endpoint to create a new dataset in automl. Requires a name parameter
 */
app.post('/datasets', async (req, res, next) => {
  try {
    const { displayName } = req.body;
    if (displayName === undefined) {
      res.status(400).send('Expected a dataset `displayName`');
      return;
    }
    if (!displayName.match(DATASET_NAME_REGEX)) {
      res
        .status(400)
        .send(
          'The displayName contains a not allowed character, the' +
            ' only allowed ones are ASCII Latin letters A-Z and a-z, an underscore (_),' +
            ' and ASCII digits 0-9'
        );
      return;
    }
    console.info(`Attempting to create dataset: ${displayName}`);
    const [response] = await createDataset(displayName);
    res.json(response);
  } catch (err) {
    res.status(500);
    res.json({message: err.message});
    console.error(err);
  }
});

/**
 * Endpoint to delete dataset from automl
 */
app.delete('/datasets/:datasetId', async (req, res, next) => {
  try {
    const { datasetId } = req.params;
    if (!datasetId) {
      res.status(400).send(`Expected datasetId: ${datasetId}`);
      return;
    }
    const name = await getDatasetName(datasetId);
    if (name === null) {
      res.status(404).send(`No dataset found for id: ${datasetId}`);
      return;
    }
    const resp = await client.deleteDataset({ name });
    console.log(resp);
    res.json();
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/**
 * Endpoint to initiate importing data for a dataset in automl.
 *
 * Inputs:
 *  - datasetId: string - automl ID of the dataset
 *  - name: string - display name of the dataset
 *  - labels: string - file name containing the labels information. e.g
 * labels.csv
 */
app.post('/import', async (req, res, next) => {
  const { name, labels, datasetId } = req.body;
  if (!name) {
    res.status(400).json({ error: 'Need a dataset name' });
    return;
  }
  if (!datasetId) {
    res.status(400).json({ error: 'Need a dataset Id' });
    return;
  }
  if (!labels) {
    res.status(400).json({ error: 'Need a path for labels file' });
    return;
  }
  try {
    const datasetName = await getDatasetName(datasetId);
    if (datasetName === null) {
      res.status(400).json({ error: 'Dataset not found' });
      return;
    }
    const operationMetadata = await importDataset(datasetName, name, labels);
    res.json(operationMetadata);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/**
 * Endpoint to initiate creation of a new model for the provided dataset
 *
 * Inputs
 *  - datasetId: string - automl ID of the dataset
 *  - trainBudget (optional)
 *  - modelType (optional)
 * Calls the create model api on AutoML
 * https://cloud.google.com/vision/automl/alpha/docs/reference/rest/v1beta1/projects.locations.models/create
 *
 * Uses the rest API
 */
app.post('/train', async (req, res, next) => {
  const { datasetId } = req.body;
  if (!datasetId) {
    res.status(400).json({ error: 'Need a dataset Id' });
    return;
  }
  let { trainBudget, modelType } = req.body;
  trainBudget = trainBudget === undefined ? DEFAULT_TRAIN_BUDGET : trainBudget;
  modelType = modelType === undefined ? DEFAULT_MODEL_TYPE : modelType;

  console.log(
    `Using train budget: ${trainBudget}, and model type: ${modelType}`
  );

  try {
    const datasetName = await getDatasetName(datasetId);
    if (datasetName === null) {
      res.status(400).json({ error: 'Dataset not found' });
      return;
    }

    const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
    const url = `${AUTOML_API_URL}/models`;

    const resp = await authClient.request({
      method: 'POST',
      data: {
        displayName: `${dayjs().format(MODEL_VERSION_FORMAT)}`,
        dataset_id: datasetId,
        imageClassificationModelMetadata: { trainBudget, modelType },
      },
      url,
    });

    const operationMetadata = resp.data as OperationMetadata;
    res.json(operationMetadata);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/**
 * Exports a model in tflite format to a gcspath
 *
 * modelId - AutoML model ID:  "ICN1119584480450950787",
 * gcsPath - Path to which model is exported
 * "gs://${AUTOML_BUCKET}/models/on-device/<folder_name>"
 *
 * Note the model will be generated in a folder with timestamp as name. For
 * more, refer to
 * https://cloud.google.com/vision/automl/alpha/docs/deploy#deployment_on_mobile_models_not_core_ml
 */
app.post('/export', async (req, res, next) => {
  const { modelId, gcsPath } = req.body;
  if (!modelId) {
    res.status(400).send('need a model id: modelId');
    return;
  }
  if (!gcsPath) {
    res.status(400).send('need a gcs path: gcsPath');
    return;
  }

  const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
  const url = `${AUTOML_API_URL}/models/${modelId}:export`;

  try {
    const operationMetadata = await authClient
      .request({
        method: 'POST',
        url,
        data: {
          output_config: {
            model_format: 'tflite',
            gcs_destination: {
              output_uri_prefix: gcsPath,
            },
          },
        },
      })
      .then(resp => resp.data as OperationMetadata);
    res.json(operationMetadata);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/**
 * Exports the latest generated model for the dataset
 */
app.post('/exportlatestmodel', async (req, res, next) => {
  const { datasetId, gcsPath } = req.body;
  if (!datasetId) {
    res.status(400).send('need a dataset id: datasetId');
    return;
  }
  if (!gcsPath) {
    res.status(400).send('need a gcs path: gcsPath');
    return;
  }

  try {
    // 1. Get all the models
    const modelsResp = (await getAllModels()).data as ModelResp;

    // 2. Filter the models for the provided dataset and get the latest model
    const datasetModels = modelsResp.model.filter(
      m =>
        m.datasetId === datasetId &&
        m.imageClassificationModelMetadata.modelType.startsWith('mobile-')
    );

    if (datasetModels === undefined) {
      throw new Error('No models found for this dataset');
    }

    // 3. Find the latest (based on createTime) model
    const latestModel = datasetModels.sort(
      (m1, m2) =>
        new Date(m2.createTime).getTime() - new Date(m1.createTime).getTime()
    )[0];

    // 3. Initiate its export
    console.log('Initiating export for the latest model', latestModel);
    const modelId = extractIdFromName(latestModel.name);
    const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
    const url = `${AUTOML_API_URL}/models/${modelId}:export`;
    const operationMetadata = await authClient
      .request({
        method: 'POST',
        url,
        data: {
          output_config: {
            model_format: 'tflite',
            gcs_destination: {
              output_uri_prefix: gcsPath,
            },
          },
        },
      })
      .then(resp => resp.data as OperationMetadata);
    res.json(operationMetadata);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/**
 * List all models - trying out the REST API
 */
app.get('/models', async (req, res, next) => {
  try {
    const resp = await getAllModels();
    res.json(resp.data);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({message: err.message});
  }
});

/** Queries all models from AutoML */
async function getAllModels() {
  const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
  const url = `${AUTOML_API_URL}/models`;
  return authClient.request({ url });
}
