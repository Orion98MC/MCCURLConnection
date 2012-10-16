//
//  MCCURLConnection.h
//
//  Created by Thierry Passeron on 02/09/12.
//  Copyright (c) 2012 Monte-Carlo Computing. All rights reserved.
//

/*
 
 MCCURLConnection is a kind of NSURLConnection with callback blocks instead of delegate.
 MCCURLConnection is meant to be very lightweight and easy to use
 MCCURLConnection is not meant to be a replacement for any full fledged network request object
 MCCURLConnection is mainly intended for HTTP requests but can work with all the other protocols handled by NSURLRequest/NSURLConnection.
 
 MCCURLConnection uses NSOperationQueue to control connections flow. You either create a connection with no specific queue (a default queue is used) or create a queue context and then create connections in this queue context. Because of the NSOperationQueue usage, you can suspend / restart, cancel and control concurency of requests.
 
 MCCURLConnection allows you to specify a global authentication delegate and few other global settings.
 
 You may wish to add categories to add missing delegate methods.
 
 REM: Don't alloc/init objects of this class, use the provided constructors
 
 
 Example usage:
 ==============
 
 * run a request in the default queue context

  NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.google.com"]];
 
  [[MCCURLConnection connectionWithRequest:request onFinished:^(MCCURLConnection *connection) {
    if (!connection.error) {
      NSLog(@"HTTP Headers: %@", [((NSHTTPURLResponse*)connection.response) allHeaderFields]);
      NSLog(@"Status: %d", connection.httpStatusCode);
      NSLog(@"Received data length: %d", connection.data.length);
    }
  }];
 
 
 * in a custom queue context
 
   NSOperationQueue *queue = [[[NSOperationQueue alloc] init]autorelease];
   queue.maxConcurrentOperationCount = 2;
   
   MCCURLConnection *context = [MCCURLConnection contextWithQueue:queue onRequest:nil];
   
   [context connectionWithRequest:request1 onFinished:^(MCCURLConnection *connection) {
     if (!connection.error) {
       NSLog(@"HTTP Headers: %@", [((NSHTTPURLResponse*)connection.response) allHeaderFields]);
       NSLog(@"Status: %d", connection.httpStatusCode);
       NSLog(@"Received data length: %d", connection.data.length);
     }
   }];
   
   MCCURLConnection *connection2 = [context connection];
   connection.onResponse = ^(NSURLResponse *response) {
     NSLog(@"Got response: %@", response);
   };
   [connection2 enqueueWithRequest:request2];
   
   ...
   
   [connection2 cancel]; // Cancel a connection
 
 REM: the queue is retained by the connection until the connection is finished or cancelled
 
*/

#import <Foundation/Foundation.h>

@interface MCCURLConnection : NSObject

@property (copy, nonatomic) void(^onResponse)(NSURLResponse *response);
@property (copy, nonatomic) void(^onData)(NSData *chunk);
@property (copy, nonatomic) void(^onFinished)(MCCURLConnection *connection);
@property (copy, nonatomic) NSCachedURLResponse *(^onWillCacheResponse)(NSCachedURLResponse *);

@property (retain, nonatomic) id userInfo; // You may set any objective-c object as userInfo

- (NSURLResponse *)response;  // Automatically set when a response is received
- (NSMutableData *)data;      // Automatically filled when no onData callback is specified
- (NSError *)error;           // Automatically set when the connection is finished with an error
- (NSInteger)httpStatusCode;  // Automatically set when a HTTP response is received
- (BOOL)isFinished;
- (BOOL)isCancelled;



#pragma mark Global settings

/* globaly set whether ongoing requested resources must be unique, default is TRUE */
+ (void)setEnforceUniqueRequestedResource:(BOOL)unique;

/* set a default onRequest callback */
+ (void)setOnRequest:(void(^)(BOOL started))callback;

/* set a default queue */
+ (void)setQueue:(NSOperationQueue *)queue;

/* set a global authentication delegate that will be used for all authentications */
+ (void)setAuthenticationDelegate:(id)aDelegate;



#pragma mark Connections

/* Return an autoreleased connection bound to the default queue */
+ (id)connection;

/* Return an enqueued connection in the default queue */
+ (id)connectionWithRequest:(NSURLRequest *)request onFinished:(void(^)(MCCURLConnection *connection))onFinishedCallback;

/* Return an autoreleased custom queue context */
+ (id)contextWithQueue:(NSOperationQueue *)queue onRequest:(void(^)(BOOL started))callback /* can be nil */;

@property (assign, nonatomic) BOOL enforcesUniqueRequestedResource;

/* Return an autoreleased connection bound to a custom queue context. ie. you must set a context first */
- (id)connection;

/* Return an enqueued connection in a custom queue context */
- (id)connectionWithRequest:(NSURLRequest *)request onFinished:(void(^)(MCCURLConnection *))onFinishedCallback;

/* enqueue the connection object in it's target queue to start the given request */
- (void)enqueueWithRequest:(NSURLRequest *)request;

/* cancel the connection */
- (void)cancel;
- (void)blockedCancel;

@end
