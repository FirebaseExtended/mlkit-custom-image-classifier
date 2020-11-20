"use strict";
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
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
exports.__esModule = true;
exports.deleteLabel = exports.deleteDataset = void 0;
var storage_1 = require("@google-cloud/storage");
var admin = require("firebase-admin");
var functions = require("firebase-functions");
var constants_1 = require("./constants");
/**
 * Clean up related metadata (labels, models, videos) from Firestore and storage
 * when a dataset is deleted
 */
exports.deleteDataset = functions.firestore
    .document('datasets/{datasetId}')
    .onDelete(function (snap, context) { return __awaiter(void 0, void 0, void 0, function () {
    var datasetId, _a, name, automlId, query_1, err_1, query_2, labelsSnapshot, err_2, query_3, err_3, query_4, err_4, autoMlBucket, files, err_5;
    return __generator(this, function (_b) {
        switch (_b.label) {
            case 0:
                datasetId = context.params.datasetId;
                _a = snap.data(), name = _a.name, automlId = _a.automlId;
                console.log("Attempting to delete dataset: " + name + " with id: " + datasetId);
                _b.label = 1;
            case 1:
                _b.trys.push([1, 3, , 4]);
                query_1 = admin
                    .firestore()
                    .collection('collaborators')
                    .where('parent_key', '==', datasetId);
                return [4 /*yield*/, new Promise(function (resolve, reject) {
                        deleteQueryBatch(admin.firestore(), query_1, 100, resolve, reject);
                    })];
            case 2:
                _b.sent();
                console.log('Successfully deleted collaborators.');
                return [3 /*break*/, 4];
            case 3:
                err_1 = _b.sent();
                console.error("Error while deleting collaborators for dataset: " + name);
                return [3 /*break*/, 4];
            case 4:
                _b.trys.push([4, 7, , 8]);
                query_2 = admin
                    .firestore()
                    .collection('labels')
                    .where('parent_key', '==', datasetId);
                return [4 /*yield*/, query_2.get()];
            case 5:
                labelsSnapshot = _b.sent();
                labelsSnapshot.docs.forEach(function (label) { return __awaiter(void 0, void 0, void 0, function () {
                    var err_6;
                    return __generator(this, function (_a) {
                        switch (_a.label) {
                            case 0:
                                _a.trys.push([0, 2, , 3]);
                                return [4 /*yield*/, deleteImagesForLabels(label.id)];
                            case 1:
                                _a.sent();
                                return [3 /*break*/, 3];
                            case 2:
                                err_6 = _a.sent();
                                console.error("Error in deleting videos for label: " + label.id);
                                return [3 /*break*/, 3];
                            case 3: return [2 /*return*/];
                        }
                    });
                }); });
                return [4 /*yield*/, new Promise(function (resolve, reject) {
                        deleteQueryBatch(admin.firestore(), query_2, 100, resolve, reject);
                    })];
            case 6:
                _b.sent();
                console.log('Successfully deleted labels.');
                return [3 /*break*/, 8];
            case 7:
                err_2 = _b.sent();
                console.error("Error while deleting labels for dataset: " + name);
                return [3 /*break*/, 8];
            case 8:
                _b.trys.push([8, 10, , 11]);
                query_3 = admin
                    .firestore()
                    .collection('models')
                    .where('dataset_id', '==', automlId);
                return [4 /*yield*/, new Promise(function (resolve, reject) {
                        deleteQueryBatch(admin.firestore(), query_3, 100, resolve, reject);
                    })];
            case 9:
                _b.sent();
                // TODO: clear all data from storage for these models
                console.log('Successfully deleted models from firestore');
                return [3 /*break*/, 11];
            case 10:
                err_3 = _b.sent();
                console.error("Error while deleting models for dataset: " + name);
                return [3 /*break*/, 11];
            case 11:
                _b.trys.push([11, 13, , 14]);
                query_4 = admin
                    .firestore()
                    .collection('operations')
                    .where('dataset_id', '==', automlId);
                return [4 /*yield*/, new Promise(function (resolve, reject) {
                        deleteQueryBatch(admin.firestore(), query_4, 100, resolve, reject);
                    })];
            case 12:
                _b.sent();
                return [3 /*break*/, 14];
            case 13:
                err_4 = _b.sent();
                console.error("Error while deleting operations for dataset: " + name);
                return [3 /*break*/, 14];
            case 14:
                _b.trys.push([14, 16, , 17]);
                autoMlBucket = new storage_1.Storage({ projectId: constants_1.PROJECT_ID }).bucket(constants_1.AUTOML_BUCKET);
                return [4 /*yield*/, autoMlBucket.getFiles({ prefix: name })];
            case 15:
                files = (_b.sent())[0];
                files.forEach(function (file) { return __awaiter(void 0, void 0, void 0, function () {
                    return __generator(this, function (_a) {
                        switch (_a.label) {
                            case 0: return [4 /*yield*/, file["delete"]()];
                            case 1:
                                _a.sent();
                                return [2 /*return*/];
                        }
                    });
                }); });
                console.log('Deleted files from automl bucket for dataset', name);
                return [3 /*break*/, 17];
            case 16:
                err_5 = _b.sent();
                console.error('Error deleting files from automl bucket for', name);
                return [3 /*break*/, 17];
            case 17: return [2 /*return*/];
        }
    });
}); });
/**
 * Clean up images under a label when a label is deleted
 */
exports.deleteLabel = functions.firestore
    .document('labels/{labelId}')
    .onDelete(function (snap, context) { return __awaiter(void 0, void 0, void 0, function () {
    var name, labelId;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                name = snap.data().name;
                labelId = context.params.labelId;
                console.log("Attempting to delete label: " + name);
                return [4 /*yield*/, deleteImagesForLabels(labelId)];
            case 1:
                _a.sent();
                return [2 /*return*/];
        }
    });
}); });
function deleteImagesForLabels(labelId) {
    var query = admin
        .firestore()
        .collection('images')
        .where('parent_key', '==', labelId);
    return new Promise(function (resolve, reject) {
        deleteQueryBatch(admin.firestore(), query, 100, resolve, reject);
    });
}
function deleteQueryBatch(db, query, batchSize, resolve, reject) {
    query
        .get()
        .then(function (snapshot) {
        // When there are no documents left, we are done
        if (snapshot.size === 0) {
            return 0;
        }
        // Delete documents in a batch
        var batch = db.batch();
        snapshot.docs.forEach(function (doc) {
            batch["delete"](doc.ref);
        });
        return batch.commit().then(function () {
            return snapshot.size;
        });
    })
        .then(function (numDeleted) {
        if (numDeleted === 0) {
            resolve.call;
            return;
        }
        // Recurse on the next process tick, to avoid
        // exploding the stack.
        process.nextTick(function () {
            deleteQueryBatch(db, query, batchSize, resolve, reject);
        });
        return;
    })["catch"](reject);
}
