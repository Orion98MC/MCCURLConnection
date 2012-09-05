//
//  MCCURLConnection.h
//  MCCHTTPDownloaderDemo
//
//  Created by Thierry Passeron on 02/09/12.
//  Copyright (c) 2012 Monte-Carlo Computing. All rights reserved.
//

/*
 
 MCCURLConnection is a kind of NSURLConnection with callback blocks instead of delegate.
 MCCURLConnection is not meant to be a replacement for any full fledged network request object, but it's meant to be very lightweight and easy to use.
 MCCURLConnection is mainly intended for HTTP requests but can work with all the other protocols handled by NSURLRequest/NSURLConnection.
 
 MCCURLConnection uses NSOperationQueue to control connections flow. You either create a connection with no specific queue (the mainQueue is used) or create a queue context and then create connections in this queue context. Because of the NSOperationQueue usage, you can suspend / restart, cancel and control concurency of requests.
 
 MCCURLConnection allows you to specify a global authentication delegate and few other global settings.
 
 You may wish to add categories to add missing delegate methods.
 
 REM: Don't alloc/init objects of this class, use the class constructors.
 
 
 Example usage:
 ==============
 
 * request in the main queue
 
 [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL]
                              onResponse:^(NSURLResponse *response) { ... }
                                  onData:^(NSData *chunk) { ... }
                              onFinished:^(NSError *error, NSInteger status) { ... }];
 
 * requests in a custom queue context
 
 NSOperationQueue *queue = [[[NSOperationQueue alloc] init]autorelease];
 queue.maxConcurrentOperationCount = 2;
 
 MCCURLConnection *context = [MCCURLConnection contextWithQueue:queue onRequest:nil];
 
 [context connectionWithRequest:[NSURLRequest requestWithURL:myURL1]
                     onResponse:^(NSURLResponse *response) { ... }
                         onData:^(NSData *chunk) { ... }
                     onFinished:^(NSError *error, NSInteger status) { ... }];
 
 MCCURLConnection *connection2 =
 [context connectionWithRequest:[NSURLRequest requestWithURL:myURL2]
                     onResponse:^(NSURLResponse *response) { ... }
                         onData:^(NSData *chunk) { ... }
                     onFinished:^(NSError *error, NSInteger status) { ... }];
 
 ...
 
 [connection2 cancel]; // Cancel a connection
 
 REM: the queue is retained by the connection until the connection is finished or canceled
 
*/

#import <Foundation/Foundation.h>

@interface MCCURLConnection : NSObject


#pragma mark Global settings

/* globaly set whether ongoing request resources must be unique, default is TRUE */
+ (void)setEnforceUniqueRequestedResource:(BOOL)unique;

/* set a global onRequest callback */
+ (void)setOnRequest:(void(^)(BOOL started))callback;

/* set a global authentication delegate that will be used for all authentications */
+ (void)setAuthenticationDelegate:(id)aDelegate;



#pragma mark Connections

/* Return an autoreleased connection in the main queue or nil if duplicate resource request and enforced policy */
+ (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(NSURLResponse *response))onResponse /* can be nil */
                     onData:(void(^)(NSData *chunk))onData /* can be nil */
                 onFinished:(void(^)(NSError *error, NSInteger status))onFinished /* can be nil */;

/* Return an autoreleased custom queue context */
+ (id)contextWithQueue:(NSOperationQueue *)queue onRequest:(void(^)(BOOL started))callback /* can be nil */;

/* Return an autoreleased connection in a custom queue context or nil if duplicate resource request and enforced policy */
- (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(NSURLResponse *response))onResponse /* can be nil */
                     onData:(void(^)(NSData *chunk))onData /* can be nil */
                 onFinished:(void(^)(NSError *error, NSInteger status))onFinished /* can be nil */;

/* cancel the connection */
- (void)cancel;

@end
