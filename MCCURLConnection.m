//
//  MCCURLConnection.m
//
//  Created by Thierry Passeron on 02/09/12.
//  Copyright (c) 2012 Monte-Carlo Computing. All rights reserved.
//

//#define DEBUG_MCCURLConnection

#ifdef DEBUG_MCCURLConnection
@interface NSURLCache (MCCURLConnectionAddons)
@end
@implementation NSURLCache (MCCURLConnectionAddons)
- (NSString *)description {
  return [NSString stringWithFormat:@"%@:\n\tDisk (u/c): %.3f MB / %.3f MB\nMemory (u/c): %.3f MB / %.3f MB", NSStringFromClass([self class]),
          (float)self.currentDiskUsage / 1000000.0f, (float)self.diskCapacity / 1000000.0f, (float)self.currentMemoryUsage / 1000000.0f, (float)self.memoryCapacity / 1000000.0f];
}
@end
#endif

#import "MCCURLConnection.h"

@interface MCCURLConnection () <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@property (retain, nonatomic) NSURLConnection *connection;
@property (retain, nonatomic) NSOperationQueue *queue;
@property (retain, nonatomic) NSString *identifier;

@property (copy, nonatomic) void(^onRequest)(BOOL started);

@property (assign, atomic) BOOL finished;
@property (assign, atomic) BOOL cancelled;
@property (assign, atomic) BOOL started;
@property (assign, nonatomic) BOOL isContext;

@property (retain, nonatomic) NSURLResponse *response;
@property (retain, nonatomic) NSMutableData *data;
@property (retain, nonatomic) NSError *error;
@property (assign, nonatomic) NSInteger httpStatusCode;

@property (assign, nonatomic) BOOL enforcesUniqueRequestedResourceFromContext;
@property (assign, nonatomic) BOOL contextual;
@end

@implementation MCCURLConnection
@synthesize connection, onRequest, onResponse, onData, onFinished, httpStatusCode, queue, finished, cancelled, identifier, started, isContext, response, data, error, onWillCacheResponse;
@synthesize userInfo, enforcesUniqueRequestedResource, enforcesUniqueRequestedResourceFromContext, contextual;


#pragma mark global settings

static BOOL _unique = TRUE;
+ (void)setEnforceUniqueRequestedResource:(BOOL)unique {
  _unique = unique;
}

static void(^globalOnRequest)(BOOL started) = nil;
+ (void)setOnRequest:(void(^)(BOOL started))callback {
  if (globalOnRequest) {
    Block_release(globalOnRequest);
  }
  globalOnRequest = callback;
  Block_copy(globalOnRequest);
}

static NSOperationQueue *defaultQueue = nil;
+ (void)setQueue:(NSOperationQueue *)queue {
  if (defaultQueue) {
    [defaultQueue release];
  }
  defaultQueue = queue;
  [defaultQueue retain];
}

static id <NSURLConnectionDelegate> _authenticationDelegate = nil;
+ (void)setAuthenticationDelegate:(id<NSURLConnectionDelegate>)authDelegate {
  _authenticationDelegate = authDelegate;
}


#pragma mark init/dealloc

static dispatch_queue_t _serialQueue = nil; /* Queue used for inter-thread sync like when cancelling a connection */
/* Warning: Don't submit anything using dispatch_sync to the main thread from this queue because of !REF1! */

- (id)init {
  self = [super init];
  if (!self) return nil;
  
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _serialQueue = dispatch_queue_create("com.serial.MCCURLConnection", NULL); // Critical section serial queue mainly used for cancels
    if (!defaultQueue) {
      defaultQueue = [[NSOperationQueue alloc]init];
      defaultQueue.maxConcurrentOperationCount = 1;
    }
    _ongoing = [[NSMutableSet alloc]init]; // Unique resource check
  });
  
  self.started = FALSE;
  self.finished = FALSE;
  self.cancelled = FALSE;
  self.isContext = FALSE;
  self.queue = defaultQueue;
  self.contextual = FALSE;
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"init: %p", self);
#endif
  
  return self;
}

- (void)dealloc {
#ifdef DEBUG_MCCURLConnection
  NSLog(@"dealloc: %@", self);
#endif
  self.response = nil;
  self.data = nil;
  self.error = nil;
  self.userInfo = nil;
  if (_unique && _ongoing && identifier) [_ongoing removeObject:identifier];
  self.identifier = nil;
  self.queue = nil;
  self.connection = nil;
  self.onRequest = nil;
  self.onResponse = nil;
  self.onData = nil;
  self.onFinished = nil;
  self.onWillCacheResponse = nil;
  [super dealloc];
}


#pragma mark connection and context management

+ (id)connection {
  return [[[[self class]alloc]init]autorelease];
}

+ (id)connectionWithRequest:(NSURLRequest *)request onFinished:(void(^)(MCCURLConnection *))onFinishedCallback {
  MCCURLConnection *c = [self connection];
  c.onFinished = onFinishedCallback;
  [c enqueueWithRequest:request];
  return c;
}

+ (id)contextWithQueue:(NSOperationQueue *)queue onRequest:(void(^)(BOOL started))callback {
  MCCURLConnection *c = [[self alloc]init];
  if (!c) return nil;
  
  c.queue = queue;
  c.onRequest = callback;
  c.isContext = TRUE;
  c.enforcesUniqueRequestedResource = YES; /* Default to enforce policy */
  
  return [c autorelease];
}

- (void)setEnforcesUniqueRequestedResource:(BOOL)does {
  NSAssert(self.isContext, @"Only on a context");
  enforcesUniqueRequestedResource = does;
}

- (id)connection {
  NSAssert(isContext == TRUE, @"Not a context. Don't use alloc/init for this class");
  
  MCCURLConnection *c = [[[self class]alloc]init];
  
  // Inherit context
  c.queue = queue;
  if (onRequest) c.onRequest = onRequest;
  c.enforcesUniqueRequestedResourceFromContext = enforcesUniqueRequestedResource;
  c.contextual = TRUE;
  
  return [c autorelease];
}

- (id)connectionWithRequest:(NSURLRequest *)request onFinished:(void(^)(MCCURLConnection *))onFinishedCallback {
  MCCURLConnection *c = [self connection];
  c.onFinished = onFinishedCallback;
  [c enqueueWithRequest:request];
  return c;
}

- (void)cancel {
#ifdef DEBUG_MCCURLConnection
  NSLog(@"Should cancel: %p", self);
#endif
  self.cancelled = TRUE; // Cancelling is not atomic, thus, you may receive delegate calls shortly after.
    
  dispatch_async(_serialQueue, ^{
    [self removeFromOngoingRequests];
#ifdef DEBUG_MCCURLConnection
    NSLog(@"Cancelling: %p", self);
#endif
    if (self.started && !self.finished) [connection cancel];
  });
}

- (void)blockedCancel { /* this cancelling blocks the caller until the cancel is effective */
  dispatch_sync(_serialQueue, ^{
#ifdef DEBUG_MCCURLConnection
    NSLog(@"blocked Cancelling: %p", self);
#endif
    self.cancelled = TRUE;
    [self removeFromOngoingRequests];
    if (self.started && !self.finished) [connection cancel];
  });
}


#pragma mark tool methods

static NSMutableSet *_ongoing = nil;
- (BOOL)setOngoingRequest:(NSURLRequest *)aRequest {
  if ((contextual && !enforcesUniqueRequestedResourceFromContext) || !_unique) {
    return YES;
  }
  
  if ([aRequest HTTPMethod]) {
    NSString *method = [[aRequest HTTPMethod]uppercaseString];
    if ([method isEqualToString:@"GET"]) {
      self.identifier = [NSString stringWithFormat:@"%@ %@", [aRequest HTTPMethod], [aRequest URL]];
    } else return TRUE; // Should md5 the request + body ?
  } else {
    self.identifier = [NSString stringWithFormat:@"%@", [aRequest URL]];
  }
  
  if ([_ongoing containsObject:identifier]) {
//#ifdef DEBUG_MCCURLConnection
    NSLog(@"Duplicate request: %p (%@)", self, identifier);
//#endif
    
    return FALSE;
  }
  [_ongoing addObject:identifier];
  return TRUE;
}

- (void)removeFromOngoingRequests {
  if ((_unique || (contextual && enforcesUniqueRequestedResourceFromContext)) && _ongoing && identifier) [_ongoing removeObject:identifier];
}

- (void)enqueueWithRequest:(NSURLRequest *)request {
  NSAssert(!isContext, @"Cannot enqueue a context. use - (id)connection; to create a connection in a context");
  
  [queue addOperationWithBlock:^{
#ifdef DEBUG_MCCURLConnection
    NSLog(@"Will start: %@", self);
#endif
    
    NSAssert(![NSThread isMainThread], @"Main thread is not allowed");
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    
    // Critical section management begin
    __block BOOL shouldReturn = FALSE;
    
    dispatch_sync(_serialQueue, ^{ /* !REF1! it is a synchronous dispatch, we wait for completion... */
      if (self.cancelled || ![self setOngoingRequest:request]) { shouldReturn = TRUE; return; }
      
      /* For the same reason don't use a dispatch_sync(_serialQueue, ...) in these callbacks */
      if (onRequest) onRequest(TRUE);
      if (globalOnRequest) globalOnRequest(TRUE);
      
      self.connection = [[[NSURLConnection alloc]initWithRequest:request delegate:self startImmediately:NO]autorelease];
      [connection scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
      [connection start];
      
      self.started = TRUE;
#ifdef DEBUG_MCCURLConnection
      NSLog(@"Started: %p", self);
#endif
      
    });
    
    if (shouldReturn) {
#ifdef DEBUG_MCCURLConnection
      NSLog(@"Did not start: %p", self);
#endif
      return;
    }
    // End critical section management
        
    while (!(self.finished || self.cancelled)) {
#ifdef DEBUG_MCCURLConnection
      NSLog(@"%p ... ", self);
#endif
      [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
    
    if (onRequest) onRequest(FALSE);
    if (globalOnRequest) globalOnRequest(FALSE);
    
    dispatch_sync(_serialQueue, ^{
      [self removeFromOngoingRequests];
    });
  }];
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"Enqueued: %p", self);
#endif
}

- (NSData *)data { return data; }
- (NSURLResponse *)response { return response; }
- (NSError *)error { return error; }
- (NSInteger)httpStatusCode { return httpStatusCode; }
- (BOOL)isFinished { return finished; }
- (BOOL)isCancelled { return cancelled; }

- (NSString *)description {
  if (isContext) {
    return [NSString stringWithFormat:@"%@ (%p) queue context: %@ (onRequest:%@)", [self class], self, queue == defaultQueue ? @"Default Queue" : queue, onRequest];
  }
  
  NSMutableString *desc = [NSMutableString stringWithFormat:@"%@ (%p) connection\n", [self class], self];
                  [desc appendFormat:@"\tStarted:          %@\n", started ? @"YES" : @"NO"];
                  [desc appendFormat:@"\tQueue:            %@\n", queue == defaultQueue ? @"Default Queue" : queue];
  if (connection) [desc appendFormat:@"\tConnection:       %@\n", connection];
  if (cancelled)  [desc appendFormat:@"\tCancelled:        %@\n", cancelled ? @"YES" : @"NO"];
  if (finished)   [desc appendFormat:@"\tFinished:         %@\n", finished ? @"YES" : @"NO"];
  if (finished)   [desc appendFormat:@"\tHTTP status code: %d\n", httpStatusCode];
  if (identifier) [desc appendFormat:@"\tIdentifier:       %@\n", identifier];
  
  if (onRequest)  [desc appendFormat:@"\tonRequest:        %@\n", onRequest];
  if (onResponse) [desc appendFormat:@"\tonResponse:       %@\n", onResponse];
  if (onData)     [desc appendFormat:@"\tonData:           %@\n", onData];
  if (onFinished) [desc appendFormat:@"\tonFinished:       %@\n", onFinished];
  
  return desc;
}


#pragma mark delegate callbacks

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)aResponse {
  if (self.cancelled) return;
  
  if ([aResponse isKindOfClass:[NSHTTPURLResponse class]]) {
    httpStatusCode = [(NSHTTPURLResponse*)aResponse statusCode];
  }

  self.response = aResponse;
  self.data = [NSMutableData data];

  if (onResponse) onResponse(response);
#ifdef DEBUG_MCCURLConnection
  NSLog(@"*** response in %p", self);
#endif
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)chunk {
  if (self.cancelled) return;
  
  if (onData) onData(chunk);
  else [data appendData:chunk];
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"*** chunk in %p", self);
#endif
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection {
  if (self.cancelled) return;
  
  self.finished = TRUE;
  if (onFinished) onFinished(self);
#ifdef DEBUG_MCCURLConnection
  NSLog(@"*** did finish %p", self);
#endif
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)anError {
  if (self.cancelled) return;
  
  self.finished = TRUE;
  self.error = anError;
  if (onFinished) onFinished(self);
#ifdef DEBUG_MCCURLConnection
  NSLog(@"*** did fail %p", self);
#endif
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"** will cache response in %p (cache: %@)", self, [NSURLCache sharedURLCache]);
#endif
  return onWillCacheResponse ? onWillCacheResponse(cachedResponse) : cachedResponse;
}



#pragma mark Authentication delegate methods

- (BOOL)connection:(NSURLConnection *)aConnection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
  return _authenticationDelegate && [_authenticationDelegate respondsToSelector:@selector(connection:canAuthenticateAgainstProtectionSpace:)] ? [_authenticationDelegate connection:aConnection canAuthenticateAgainstProtectionSpace:protectionSpace] : NO;
}

- (void)connection:(NSURLConnection *)aConnection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  if (_authenticationDelegate  && [_authenticationDelegate respondsToSelector:@selector(connection:didCancelAuthenticationChallenge:)])
    [_authenticationDelegate connection:aConnection didCancelAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)aConnection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  if (_authenticationDelegate  && [_authenticationDelegate respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)])
    [_authenticationDelegate connection:aConnection didReceiveAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)aConnection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  if (_authenticationDelegate  && [_authenticationDelegate respondsToSelector:@selector(connection:willSendRequest:redirectResponse:)])
    [_authenticationDelegate connection:aConnection willSendRequestForAuthenticationChallenge:challenge];
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)aConnection {
  return _authenticationDelegate   && [_authenticationDelegate respondsToSelector:@selector(connectionShouldUseCredentialStorage:)] ? [_authenticationDelegate connectionShouldUseCredentialStorage:aConnection] : YES;
}

@end
