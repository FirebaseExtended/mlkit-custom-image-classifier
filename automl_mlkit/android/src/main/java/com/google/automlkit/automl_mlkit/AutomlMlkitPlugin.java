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

package com.google.automlkit.automl_mlkit;

import android.net.Uri;
import android.os.SystemClock;
import androidx.annotation.NonNull;

import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.firebase.ml.common.FirebaseMLException;
import com.google.firebase.ml.common.modeldownload.FirebaseLocalModel;
import com.google.firebase.ml.common.modeldownload.FirebaseModelManager;
import com.google.firebase.ml.vision.FirebaseVision;
import com.google.firebase.ml.vision.common.FirebaseVisionImage;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabel;
import com.google.firebase.ml.vision.label.FirebaseVisionImageLabeler;
import com.google.firebase.ml.vision.label.FirebaseVisionOnDeviceAutoMLImageLabelerOptions;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.util.Map;

public class AutomlMlkitPlugin implements MethodCallHandler {

  private final Registrar registrar;

  private FirebaseVisionImageLabeler labeler;

  private static final String RUN_MODEL_ON_IMAGE_METHOD = "runModelOnImage";
  private static final String LOAD_MODEL_FROM_CACHE_METHOD = "loadModelFromCache";
  private static final String MANIFEST_FILE = "manifest.json";

  /**
   * Plugin registration.
   */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "automl_mlkit");
    channel.setMethodCallHandler(new AutomlMlkitPlugin(registrar));
  }

  private AutomlMlkitPlugin(Registrar registrar) {
    this.registrar = registrar;
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    switch (call.method) {
      case LOAD_MODEL_FROM_CACHE_METHOD: {
        // TODO: This should take a dataset name or model name. For now, just load the model
        // from the cached dir
        try {
          String datasetName = call.argument("dataset");
          loadModelFromCache(datasetName, result);
        } catch (Exception e) {
          result.error("load_model", e.getMessage(), e);
        }
        break;
      }
      case RUN_MODEL_ON_IMAGE_METHOD: {
        try {
          String imagePath = call.argument("imagePath");
          runModelOnImage(imagePath, result);
        } catch (Exception e) {
          result.error("run_model_on_image", e.getMessage(), e);
        }
        break;
      }
      default: {
        result.notImplemented();
        break;
      }
    }
  }

  /**
   * Creates a new labeler based on the contents of manifest.json in app's cache dir
   */
  private void loadModelFromCache(String datasetName, Result result) throws Exception {
    // create a new unique model name for MLKit
    String modelName = datasetName + SystemClock.elapsedRealtime();

    File datasetFolder = new File(registrar.context().getCacheDir(), datasetName);
    File manifestJson = new File(datasetFolder, MANIFEST_FILE);
    FirebaseLocalModel localModel = new FirebaseLocalModel.Builder(modelName)
        .setFilePath(manifestJson.getAbsolutePath())
        .build();
    FirebaseModelManager.getInstance().registerLocalModel(localModel);

    // construct the options
    FirebaseVisionOnDeviceAutoMLImageLabelerOptions labelerOptions =
        new FirebaseVisionOnDeviceAutoMLImageLabelerOptions.Builder()
            .setLocalModelName(modelName)
            .build();

    labeler = FirebaseVision.getInstance().getOnDeviceAutoMLImageLabeler(labelerOptions);
    result.success(null);
  }

  /**
   * Runs an inference on an image. Note: model needs to be loaded before an inference can be run
   */
  private void runModelOnImage(String imagePath, final Result result) throws FirebaseMLException {
    FirebaseVisionImage image;

    try {
      image = readImageFromPath(imagePath);
    } catch (IOException e) {
      result.error("run_model_on_image", e.getMessage(), e);
      return;
    }

    labeler.processImage(image)
        .addOnSuccessListener(new OnSuccessListener<List<FirebaseVisionImageLabel>>() {
          @Override
          public void onSuccess(List<FirebaseVisionImageLabel> firebaseVisionImageLabels) {
            List<Map<String, Object>> labels = new ArrayList<>(firebaseVisionImageLabels.size());
            for (FirebaseVisionImageLabel label : firebaseVisionImageLabels) {
              Map<String, Object> labelData = new HashMap<>();
              labelData.put("confidence", (double) label.getConfidence());
              labelData.put("label", label.getText());
              labels.add(labelData);
            }
            result.success(labels);
          }
        }).addOnFailureListener(
        new OnFailureListener() {
          @Override
          public void onFailure(@NonNull Exception e) {
            result.error("run_model_on_image", e.getMessage(), e);
          }
        });
  }

  // TODO: account for rotation
  private FirebaseVisionImage readImageFromPath(String imagePath) throws IOException {
    File imageFile = new File(imagePath);
    return FirebaseVisionImage.fromFilePath(registrar.context(), Uri.fromFile(imageFile));
  }
}
