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

#import "AutomlMlkitPlugin.h"

@import FirebaseMLCommon;
@import FirebaseMLVision;
@import FirebaseMLVisionAutoML;

@interface AutomlMlkitPlugin ()
@property(nonatomic, retain) FlutterMethodChannel *channel;
@property(nonatomic, retain) FIRVisionImageLabeler *labeler;
@end

@implementation AutomlMlkitPlugin

+ (void) registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"automl_mlkit" binaryMessenger:[registrar messenger]];
    AutomlMlkitPlugin *instance = [[AutomlMlkitPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void) handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"loadModelFromCache" isEqualToString:call.method]) {
        NSString *datasetName = (NSString*) call.arguments[@"dataset"];
        NSURL *url = [[[self getCacheDirectory] URLByAppendingPathComponent:datasetName] URLByAppendingPathComponent:@"manifest.json"];

        // construct model name using the dataset name and current timestamp
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *intervalString = [NSString stringWithFormat:@"%f", now];
        NSString *modelName = [datasetName stringByAppendingString:intervalString];
        
        // register the model
        FIRLocalModel *localModel = [[FIRLocalModel alloc] initWithName:modelName path:url.path];
        [[FIRModelManager modelManager] registerLocalModel:localModel];
        FIRVisionOnDeviceAutoMLImageLabelerOptions *options =
            [[FIRVisionOnDeviceAutoMLImageLabelerOptions alloc] initWithRemoteModelName:nil localModelName:modelName];
        _labeler = [[FIRVision vision] onDeviceAutoMLImageLabelerWithOptions:options];
        result(@"success");
    }
    else if ([@"runModelOnImage" isEqualToString:call.method]) {
        NSString *imagePath = (NSString*) call.arguments[@"imagePath"];
        UIImage *uiImage = [UIImage imageWithContentsOfFile:imagePath];
        FIRVisionImage *image = [[FIRVisionImage alloc] initWithImage:uiImage];
        [_labeler processImage:image
                    completion:^(NSArray<FIRVisionImageLabel *> *_Nullable labels,
                                 NSError *_Nullable error) {
                        if (error != nil || labels == nil) {
                            FlutterError *flutterError = [FlutterError
                                                          errorWithCode:@"UNAVAILABLE"
                                                          message:@"Error while processing image"
                                                          details:error];
                            result(flutterError);
                        }
                        NSMutableDictionary *labelsDict = [[NSMutableDictionary alloc] init];
                        for (FIRVisionImageLabel *label in labels) {
                            labelsDict[@"label"] = label.text;
                            labelsDict[@"confidence"] = label.confidence;
                        }
                        result(@[labelsDict]);
                    }];
        
    }
    else {
        result(FlutterMethodNotImplemented);
    }
}

- (NSURL*) getCacheDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSURL *cachesDirectory = [fm URLForDirectory:NSCachesDirectory
                                        inDomain:NSUserDomainMask
                               appropriateForURL:nil
                                          create:YES
                                           error:&error];
    return cachesDirectory;
}

@end
