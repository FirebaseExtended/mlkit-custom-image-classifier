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

const request = require('supertest');
const sinon = require('sinon');
const { assert } = require('chai');
const automl = require('@google-cloud/automl');

describe('AutoML Api', () => {
  let app;
  const sandbox = sinon.createSandbox();

  before(() => {
    app = require('../lib/automlapi').app;
    return cleanup();
  });

  const cleanup = () => {
    sandbox.restore();
  };

  afterEach(() => {
    return cleanup();
  });

  describe('create dataset', () => {
    it('throws 400 with no dataset name', done => {
      request(app)
        .post('/create')
        .expect(400)
        .end(err => {
          if (err) throw err;
          done();
        });
    });

    it('throws 400 for a dataset of invalid format', done => {
      request(app)
        .post('/create')
        .send({ name: 'apples and oranges' })
        .set('Accept', 'application/json')
        .expect(400)
        .end(err => {
          if (err) throw err;
          done();
        });
    });

    it('gives 200 for a dataset of correct format', done => {
      const dataset = 'apples';
      sandbox
        .stub(automl.v1beta1.AutoMlClient.prototype, 'createDataset')
        .returns(Promise.resolve([dataset]));

      request(app)
        .post('/create')
        .send({ name: dataset })
        .set('Accept', 'application/json')
        .expect(200)
        .end((err, res) => {
          assert.equal(
            res.text,
            `Your dataset: ${dataset} has been successfully saved`
          );
          if (err) throw err;
          done();
        });
    });
  });

  describe('train model', () => {
    it('throws 400 with no dataset name', done => {
      request(app)
        .post('/train')
        .set('Accept', 'application/json')
        .expect(400)
        .end((err, { text }) => {
          assert.equal(text, 'Need a dataset name');
          if (err) throw err;
          done();
        });
    });

    it('gives 200 when dataset name is provided', done => {
      const dataset = 'apples';
      sandbox
        .stub(automl.v1beta1.AutoMlClient.prototype, 'listDatasets')
        .returns(
          Promise.resolve([[{ displayName: dataset, name: 'datasets/ID123' }]])
        );

      sandbox
        .stub(automl.v1beta1.AutoMlClient.prototype, 'createModel')
        .returns(Promise.resolve([{}, { operation: '123' }]));

      request(app)
        .post('/train')
        .send({ name: dataset })
        .set('Accept', 'application/json')
        .expect(200)
        .end((err, { body }) => {
          assert.deepEqual(body, { operation: '123' });
          if (err) throw err;
          done();
        });
    });
  });

  describe('import dataset', () => {
    it('throws 400 with no dataset name', done => {
      request(app)
        .post('/import')
        .send({ labels: 'something.csv' })
        .set('Accept', 'application/json')
        .expect(400)
        .end((err, { text }) => {
          assert.equal(text, 'Need a dataset name');
          if (err) throw err;
          done();
        });
    });

    it('throws 400 with no labels file', done => {
      request(app)
        .post('/import')
        .send({ name: 'apples' })
        .set('Accept', 'application/json')
        .expect(400)
        .end((err, { text }) => {
          assert.equal(text, 'Need a path for labels file');
          if (err) throw err;
          done();
        });
    });

    describe('list datasets', () => {
      it('throws 404 if the dataset is not found', done => {
        sandbox
          .stub(automl.v1beta1.AutoMlClient.prototype, 'listDatasets')
          .returns(Promise.resolve([[{ displayName: 'bananas' }]]));

        request(app)
          .post('/import')
          .send({ name: 'apples', labels: 'labels.csv' })
          .set('Accept', 'application/json')
          .expect(404)
          .end((err, { text }) => {
            assert.equal(text, 'Dataset: apples was not found.');
            if (err) throw err;
            done();
          });
      });

      it('gives 200 if dataset is found', done => {
        const dataset = 'apples';
        sandbox
          .stub(automl.v1beta1.AutoMlClient.prototype, 'listDatasets')
          .returns(Promise.resolve([[{ displayName: dataset }]]));

        sandbox
          .stub(automl.v1beta1.AutoMlClient.prototype, 'importData')
          .returns(Promise.resolve([{}, { operation: '123' }]));

        request(app)
          .post('/import')
          .send({ name: dataset, labels: 'labels.csv' })
          .set('Accept', 'application/json')
          .expect(200)
          .end((err, { body }) => {
            assert.deepEqual(body, { operation: '123' });
            if (err) throw err;
            done();
          });
      });
    });
  });
});
