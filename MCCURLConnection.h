//
//  MCCURLConnection.h
//
//  Created by Thierry Passeron on 02/09/12.
//  Copyright (c) 2012 Monte-Carlo Computing. All rights reserved.
//

/*
 
 MCCURLConnection is a kind of NSURLConnection with callback blocks instead of delegate.
 MCCURLConnection is not meant to be a replacement for any full fledged network request object, but it's meant to be very lightweight and easy to use.
 MCCURLConnection is mainly intended for HTTP requests but can work with all the other protocols handled by NSURLRequest/NSURLConnection.
 
 MCCURLConnection uses NSOperationQueue to control connections flow. You either create a connection with no specific queue (a default queue is used) or create a queue context and then create connections in this queue context. Because of the NSOperationQueue usage, you can suspend / restart, cancel and control concurency of requests.
 
 MCCURLConnection allows you to specify a global authentication delegate and few other global settings.
 
 You may wish to add categories to add missing delegate methods.
 
 REM: Don't alloc/init objects of this class, use the class constructors.
 
 
 Example usage:
 ==============
 
 * request in the default queue
 
 [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL]
                              onResponse:^(MCCURLConnection *connection, NSURLResponse *response) { ... }
                                  onData:^(MCCURLConnection *connection, NSData *chunk) { ... }
                              onFinished:^(MCCURLConnection *connection) { ... }];
 
 * requests in a custom queue context
 
 NSOperationQueue *queue = [[[NSOperationQueue alloc] init]autorelease];
 queue.maxConcurrentOperationCount = 2;
 
 MCCURLConnection *context = [MCCURLConnection contextWithQueue:queue onRequest:nil];
 
 [context connectionWithRequest:[NSURLRequest requestWithURL:myURL1]
                     onResponse:^(MCCURLConnection *connection, NSURLResponse *response) { ... }
                         onData:^(MCCURLConnection *connection, NSData *chunk) { ... }
                     onFinished:^(MCCURLConnection *connection) { ... }];
 
 MCCURLConnection *connection2 =
 [context connectionWithRequest:[NSURLRequest requestWithURL:myURL2]
                     onResponse:^(MCCURLConnection *connection, NSURLResponse *response) { ... }
                         onData:^(MCCURLConnection *connection, NSData *chunk) { ... }
                     onFinished:^(MCCURLConnection *connection) { ... }];
 
 ...
 
 [connection2 cancel]; // Cancel a connection
 
 REM: the queue is retained by the connection until the connection is finished or cancelled
 
*/

#import <Foundation/Foundation.h>

@interface MCCURLConnection : NSObject

@property (retain, nonatomic) id userInfo; // You may set any objective-c object as userInfo

- (NSURLResponse *)response;  // Automatically set when a response is received
- (NSMutableData *)data;      // Set when no onData callback is specified
- (NSError *)error;           // Automatically set when the connection is finished with an error
- (NSInteger)httpStatusCode;  // Automatically set when a HTTP response is received


#pragma mark Global settings

/* globaly set whether ongoing request resources must be unique, default is TRUE */
+ (void)setEnforceUniqueRequestedResource:(BOOL)unique;

/* set a default onRequest callback */
+ (void)setOnRequest:(void(^)(BOOL started))callback;

/* set a default queue */
+ (void)setQueue:(NSOperationQueue *)queue;

/* set a global authentication delegate that will be used for all authentications */
+ (void)setAuthenticationDelegate:(id)aDelegate;


#pragma mark Connections

/* Return an autoreleased connection in the default queue or nil if duplicate resource request and enforced policy */
+ (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(MCCURLConnection *, NSURLResponse *response))onResponseCallback
                     onData:(void(^)(MCCURLConnection *, NSData *data))onDataCallback
                 onFinished:(void(^)(MCCURLConnection *))onFinishedCallback;
/* Shortcut, data will be automatically saved */
+ (id)connectionWithRequest:(NSURLRequest *)request finished:(void(^)(MCCURLConnection *))onFinishedCallback;

/* Return an autoreleased custom queue context */
+ (id)contextWithQueue:(NSOperationQueue *)queue onRequest:(void(^)(BOOL started))callback /* can be nil */;

/* Return an autoreleased connection in a custom queue context or nil if duplicate resource request and enforced policy */
- (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(MCCURLConnection *, NSURLResponse *response))onResponseCallback
                     onData:(void(^)(MCCURLConnection *, NSData *data))onDataCallback
                 onFinished:(void(^)(MCCURLConnection *))onFinishedCallback;
/* Shortcut, data will be automatically saved */
- (id)connectionWithRequest:(NSURLRequest *)request finished:(void(^)(MCCURLConnection *))onFinishedCallback;

/* cancel the connection */
- (void)cancel;

@end
