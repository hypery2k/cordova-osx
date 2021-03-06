/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */


#import "ShellUtils.h"
#import <Cocoa/Cocoa.h>
#import <Security/Authorization.h>
#import "CDVPlugin.h"

@implementation ShellUtils

+ (BOOL) restartComputer
{
    NSAppleScript* script = [[NSAppleScript alloc] initWithSource:@"tell application \"System Events\" to restart"];
    NSDictionary* errorInfo;
    NSAppleEventDescriptor* descriptor = [script executeAndReturnError:&errorInfo];
    
    return (descriptor != nil);
}

+ (void) quitApp
{
    [[NSApplication sharedApplication] terminate:nil];    
}

+ (NSTask*) shellTask:(NSString*)command
{
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/sh"];
    [task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
    [task setArguments: @[@"-c", command]];
    
    return task;
}

+ (NSString*) executeShellTask:(NSString*)command
{
    NSPipe* pipe = [NSPipe pipe];
    NSFileHandle* fileHandle = [pipe fileHandleForReading];
    
    NSTask* task = [[self class] shellTask:command];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    [task launch];
    
    NSData* outputData = [fileHandle readDataToEndOfFile];
    
	return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

+ (NSTask*) executeShellTaskAsync:(NSString*)command withInput:(NSString*)data usingBlock:(void (^)(NSNotification *))block
{
    NSPipe* opipe = [NSPipe pipe];
    NSPipe* ipipe = [NSPipe pipe];

    NSFileHandle* ifileHandle = [ipipe fileHandleForReading];
    NSFileHandle* ofileHandle = [opipe fileHandleForWriting];

    NSTask* task = [[self class] shellTask:command];
    if (data != nil) {
        [task setStandardInput:opipe];
    }
    [task setStandardOutput:ipipe];
    [task setStandardError:ipipe];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    
    [center addObserverForName:NSFileHandleReadCompletionNotification object:ifileHandle queue:mainQueue usingBlock:block];
  // this should not be necessary, the task will close the output handle
	// [center addObserverForName:NSTaskDidTerminateNotification object:task queue:mainQueue usingBlock:block];

    [ifileHandle readInBackgroundAndNotify];
    if (data != nil) {
        [ofileHandle writeData:[data dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [task launch];
    [ofileHandle closeFile];
  
    return task;
}

+ (void) executeShellTaskAsync:(NSString*)command withInput:(NSString*)input withCallbackId:(NSString*)aCallbackId forPlugin:(CDVPlugin*)plugin;
{
    __block NSString* callbackId = aCallbackId;
    __block NSTask* task = nil;
    __block NSMutableString* outputString = [NSMutableString string];

    task = [[self class] executeShellTaskAsync:command withInput:input usingBlock:^(NSNotification* notif){
        int status = 0;

        if ([notif.object isKindOfClass:[NSFileHandle class]]) {
            NSFileHandle* fileHandle = (NSFileHandle*)notif.object;
            NSData* data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];
            NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [outputString appendString:output];
            
            if (task && [task isRunning]) {
                [fileHandle readInBackgroundAndNotify];
            } else {
                status = [task terminationStatus];
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                        messageAsDictionary:@{ @"resultcode" :[NSNumber numberWithInt:status], @"data" :outputString }];
                result.keepCallback = [NSNumber numberWithBool:NO];
                [plugin.commandDelegate sendPluginResult:result callbackId:callbackId];
            }
        }
    }];
}


@end
