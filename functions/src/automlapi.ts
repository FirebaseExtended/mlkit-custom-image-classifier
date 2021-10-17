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

const automl = require('@google-cloud/automl');
import * as dayjs from "dayjs";
import * as express from "express";
import { GoogleAuth } from "google-auth-library";
import * as morgan from "morgan";
import {
  AUTOML_API_SCOPE,
  AUTOML_API_URL,
  AUTOML_BUCKET_URL,
  LOCATION,
  PROJECT_ID,
} from "./constants";
import { OperationMetadata } from "./types";

export const app = express();
app.use(express.json());
app.use(morgan("combined"));

const googleAuth = new GoogleAuth({
  scopes: 'https://www.googleapis.com/auth/cloud-platform'
});
const client = new automl.v1beta1.AutoMlClient();
const util = require('util');

// Controls model type. For more options, see:
// https://cloud.google.com/vision/automl/alpha/docs/reference/rest/v1beta1/projects.locations.models#imageclassificationmodelmetadata
const DEFAULT_MODEL_TYPE = "mobile-high-accuracy-1";

const DEFAULT_TRAIN_BUDGET = 1;
const DATASET_NAME_REGEX = new RegExp("^[a-zA-Z_0-9]+$");
const MODEL_VERSION_FORMAT = "vYYYYMMDDHHmmss";
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
async function createDataset(displayName: String): Promise<any> {
  const dataset = {
    name: displayName,
    displayName,
    imageClassificationDatasetMetadata: {
      classificationType: "MULTICLASS",
    },
  };
  return client.createDataset({ parent: parent, dataset: dataset });
}

const extractIdFromName = (datasetName: string): string => {
  const parts = datasetName.split("/");
  return parts[parts.length - 1];
};

/// returns the ID of a dataset of the format ICN** or null if not found
function getDatasetName(automlId: string): Promise<string | null> {
  return client.listDatasets({ parent }).then((responses: any[]) => {
    const datasets = responses[0];
    for (const dataset of datasets) {
      if (extractIdFromName(dataset["name"]) === automlId) {
        return dataset["name"];
      }
    }
  });
}

/// initiates an operation on automl to start importing data for a dataset
async function importDataset(
  name: string,
  displayName: string,
  labels: string
): Promise<any> {
  const inputConfig = {
    gcsSource: {
      inputUris: [`${AUTOML_BUCKET_URL}/${displayName}/${labels}`],
    },
  };

  // return await client
  //   .importData({ name: name, inputConfig: inputConfig })
  //   .then((responses: any[]) => responses[0].promise());
  //initial api response with operation metadata
  const [responses] = await client
    .importData({ name: name, inputConfig: inputConfig });

  const operation = responses[0];
  console.log('Processing import...');
  //await listOperationStatus();
  // const [finalResp] = await operation.promise();
  // const operationDetails = finalResp[2];

  // // Get the data import details.
  // console.log('Data import details:');
  // console.log('\tOperation details:');
  // console.log(`\t\tName: ${operationDetails.name}`);
  // console.log(`\t\tDone: ${operationDetails.done}`);
  return responses;

  // return responses[0];
  //  return 
  //     .then(responses => {
  //       const operation = responses[0];
  //       console.log('Processing import...');
  //       return await operation.promise();
  //     })
  //     .then(responses => {
  //       // The final result of the operation.
  //       const operationDetails = responses[2];

  //       // Get the data import details.
  //       console.log('Data import details:');
  //       console.log('\tOperation details:');
  //       console.log(`\t\tName: ${operationDetails.name}`);
  //       console.log(`\t\tDone: ${operationDetails.done}`);
  //     })
  //     .catch(err => {
  //       console.error(err);
  //       return err;
  //     });
  // });
}

/**
 * List all datasets
 */
app.get("/datasets", async (req, res, next) => {
  try {
    const authClient = await googleAuth.getClient();
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
app.post("/datasets", async (req, res, next) => {
  try {
    const { displayName } = req.body;
    if (displayName === undefined) {
      res.status(400).send("Expected a dataset `displayName`");
      return;
    }
    if (!displayName.match(DATASET_NAME_REGEX)) {
      res
        .status(400)
        .send(
          "The displayName contains a not allowed character, the" +
          " only allowed ones are ASCII Latin letters A-Z and a-z, an underscore (_)," +
          " and ASCII digits 0-9"
        );
      return;
    }
    console.info(`Attempting to create dataset: ${displayName}`);
    const [response] = await createDataset(displayName);
    res.json(response);
  } catch (err) {
    res.status(500);
    res.json({ message: err.message });
    console.error(err);
  }
});

/**
 * Endpoint to delete dataset from automl
 */
app.delete("/datasets/:datasetId", async (req, res, next) => {
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
    res.json({ message: err.message });
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
app.post("/import", async (req, res, next) => {
  const { name, labels, datasetId } = req.body;
  if (!name) {
    res.status(400).json({ error: "Need a dataset name" });
    return;
  }
  if (!datasetId) {
    res.status(400).json({ error: "Need a dataset Id" });
    return;
  }
  if (!labels) {
    res.status(400).json({ error: "Need a path for labels file" });
    return;
  }
  try {
    const datasetName = await getDatasetName(datasetId);
    if (datasetName === null) {
      res.status(400).json({ error: "Dataset not found" });
      return;
    }
    const operationMetadata = await importDataset(datasetName, name, labels);
    res.json(operationMetadata);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({ message: err.message });
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
app.post("/train", async (req, res, next) => {
  console.log(
    `Training function execute`
  );
  const { datasetId } = req.body;
  if (!datasetId) {
    res.status(400).json({ error: "Need a dataset Id" });
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
      res.status(400).json({ error: "Dataset not found" });
      return;
    }

    // const authClient = await auth.getClient({ scopes: [AUTOML_API_SCOPE] });
    // const url = `${AUTOML_API_URL}/models`;

    const request = {
      parent: parent,
      model: {
        displayName: `${dayjs().format(MODEL_VERSION_FORMAT)}`,
        datasetId: datasetId,
        imageClassificationModelMetadata: { trainBudget, modelType }, // Leave unset, to use the default base model
      },
    };

    const [operation] = await client.createModel(request);
    console.log('Training started...');
    console.log(`Training operation name: ${operation.name}`);
    console.log(`Training operation metadata: ${operation.metadata}`);
    res.json(operation);
    // await listOperationStatus();
    // const modelId = extractIdFromName(`${dayjs().format(MODEL_VERSION_FORMAT)}`);
    // console.log(`model id: ${modelId}`);
    // await deployModel(modelId);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({ message: err.message });
  }
});

async function listOperationStatus(): Promise<any> {
  // Construct request
  const request = {
    name: parent,
    filter: '',
  };

  const [response] = await client.operationsClient.listOperations(request);
  console.log('List of operation status:');
  for (const operation of response) {
    console.log(`Name: ${operation.name}`);
    console.log('Operation details:');
    console.log(`${operation.done}`);
    console.log(`${operation.metadata.updateTime}`);
    // manageTraining
  }
}

async function deployModel(modelId: string) {
  // Construct request
  const request = {
    name: client.modelPath(PROJECT_ID, LOCATION, modelId),
  };

  const [operation] = await client.deployModel(request);

  // Wait for operation to complete.
  const [response] = await operation.promise();
  console.log(`Model deployment finished. ${response}`);
}

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
app.post("/export", async (req, res, next) => {
  const { modelId, gcsPath } = req.body;
  if (!modelId) {
    res.status(400).send("need a model id: modelId");
    return;
  }
  if (!gcsPath) {
    res.status(400).send("need a gcs path: gcsPath");
    return;
  }

  const authClient = await googleAuth.getClient();
  const url = `${AUTOML_API_URL}/models/${modelId}:export`;

  try {
    const operationMetadata = await authClient
      .request({
        method: "POST",
        url,
        data: {
          output_config: {
            model_format: "tflite",
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
    res.json({ message: err.message });
  }
});

/**
 * Exports the latest generated model for the dataset
 */
app.post("/exportlatestmodel", async (req, res, next) => {
  const { datasetId, gcsPath } = req.body;
  if (!datasetId) {
    res.status(400).send("need a dataset id: datasetId");
    return;
  }
  if (!gcsPath) {
    res.status(400).send("need a gcs path: gcsPath");
    return;
  }

  try {
    // 1. Get all the models
    const modelsResp = (await getAllModels()).data as ModelResp;

    // 2. Filter the models for the provided dataset and get the latest model
    const datasetModels = modelsResp.model.filter(
      m =>
        m.datasetId === datasetId &&
        m.imageClassificationModelMetadata.modelType.startsWith("mobile-")
    );

    if (datasetModels === undefined) {
      throw new Error("No models found for this dataset");
    }

    // 3. Find the latest (based on createTime) model
    const latestModel = datasetModels.sort(
      (m1, m2) =>
        new Date(m2.createTime).getTime() - new Date(m1.createTime).getTime()
    )[0];

    // 3. Initiate its export
    console.log("Initiating export for the latest model", latestModel);
    const modelId = extractIdFromName(latestModel.name);
    const authClient = await googleAuth.getClient();
    const url = `${AUTOML_API_URL}/models/${modelId}:export`;
    const operationMetadata = await authClient
      .request({
        method: "POST",
        url,
        data: {
          output_config: {
            model_format: "tflite",
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
    res.json({ message: err.message });
  }
});

/**
 * List all models - trying out the REST API
 */
app.get("/models", async (req, res, next) => {
  try {
    const resp = await getAllModels();
    res.json(resp.data);
  } catch (err) {
    console.error(err);
    res.status(500);
    res.json({ message: err.message });
  }
});


/** Queries all models from AutoML */
async function getAllModels() {
  const authClient = await googleAuth.getClient();
  const url = `${AUTOML_API_URL}/models`;
  return authClient.request({ url });
}
