//
//  MCCURLConnection.m
//
//  Created by Thierry Passeron on 02/09/12.
//  Copyright (c) 2012 Monte-Carlo Computing. All rights reserved.
//

//#define DEBUG_MCCURLConnection

#import "MCCURLConnection.h"

@interface MCCURLConnection () <NSURLConnectionDelegate>
@property (retain, nonatomic) NSURLConnection *connection;
@property (retain, nonatomic) NSOperationQueue *queue;
@property (retain, nonatomic) NSString *identifier;

@property (copy, nonatomic) void(^onRequest)(BOOL started);
@property (copy, nonatomic) void(^onResponse)(MCCURLConnection *, NSURLResponse *);
@property (copy, nonatomic) void(^onData)(MCCURLConnection *, NSData *);
@property (copy, nonatomic) void(^onFinished)(MCCURLConnection *);

@property (assign, atomic) BOOL finished;
@property (assign, atomic) BOOL cancelled;
@property (assign, atomic) BOOL started;
@property (assign, nonatomic) BOOL isContext;

@property (retain, nonatomic) NSURLResponse *response;
@property (retain, nonatomic) NSMutableData *data;
@property (retain, nonatomic) NSError *error;
@property (assign, nonatomic) NSInteger httpStatusCode;

@end

@implementation MCCURLConnection
@synthesize connection, onRequest, onResponse, onData, onFinished, httpStatusCode, queue, finished, cancelled, identifier, started, isContext, response, data, error;
@synthesize userInfo;


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
  if (!(self = [super init])) return nil;
  
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
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"init: %p", self);
#endif
  
  return self;
}

- (id)initWithRequest:(NSURLRequest *)request
           onResponse:(void(^)(MCCURLConnection *, NSURLResponse*))onResponseCallback
               onData:(void(^)(MCCURLConnection *, NSData *chunk))onDataCallback
           onFinished:(void(^)(MCCURLConnection *))onFinishedCallback {
  if (!(self = [self init])) return nil;
  
  if (_unique && ![self setOngoingRequest:request]) {
    [self autorelease];
    return nil;
  }
  
  self.onResponse = onResponseCallback;
  self.onData = onDataCallback;
  self.onFinished = onFinishedCallback;
  
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
  [super dealloc];
}


#pragma mark connection and context management

+ (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(MCCURLConnection *, NSURLResponse *response))onResponseCallback
                     onData:(void(^)(MCCURLConnection *, NSData *data))onDataCallback
                 onFinished:(void(^)(MCCURLConnection *))onFinishedCallback {
  
  MCCURLConnection *c = [[[self class]alloc]initWithRequest:request onResponse:onResponseCallback onData:onDataCallback onFinished:onFinishedCallback];
  
  [c enqueueRequest:request];
  
  return [c autorelease];
}

+ (id)contextWithQueue:(NSOperationQueue *)queue onRequest:(void(^)(BOOL started))callback {
  MCCURLConnection *c = [[self alloc]init];
  if (!c) return nil;
  
  c.queue = queue;
  c.onRequest = callback;
  c.isContext = TRUE;
  
  return [c autorelease];
}

- (id)connectionWithRequest:(NSURLRequest *)request
                 onResponse:(void(^)(MCCURLConnection *, NSURLResponse *response))onResponseCallback
                     onData:(void(^)(MCCURLConnection *, NSData *data))onDataCallback
                 onFinished:(void(^)(MCCURLConnection *))onFinishedCallback {
  
  NSAssert(isContext == TRUE, @"Not a context");
  
  MCCURLConnection *c = [[[self class]alloc]initWithRequest:request onResponse:onResponseCallback onData:onDataCallback onFinished:onFinishedCallback];
  
  // Inherit context
  c.queue = queue;
  if (onRequest) c.onRequest = onRequest;
  
  [c enqueueRequest:request];
  
  return [c autorelease];
}

- (void)cancel {
  self.cancelled = TRUE; // Cancelling is not atomic, thus, you may receive delegate calls shortly after.
  dispatch_async(_serialQueue, ^{
#ifdef DEBUG_MCCURLConnection
    NSLog(@"Cancelling: %p", self);
#endif
    if (self.started && !self.finished) [connection cancel];
  });
}

#pragma mark shortcut methods
+ (id)connectionWithRequest:(NSURLRequest *)request finished:(void(^)(MCCURLConnection *))onFinishedCallback {
  return [self connectionWithRequest:request onResponse:nil onData:nil onFinished:onFinishedCallback];
}

- (id)connectionWithRequest:(NSURLRequest *)request finished:(void(^)(MCCURLConnection *))onFinishedCallback {
  return [self connectionWithRequest:request onResponse:nil onData:nil onFinished:onFinishedCallback];
}

#pragma mark tool methods

static NSMutableSet *_ongoing = nil;
- (BOOL)setOngoingRequest:(NSURLRequest *)aRequest {
  if ([aRequest HTTPMethod]) {
    NSString *method = [[aRequest HTTPMethod]uppercaseString];
    if ([method isEqualToString:@"GET"]) {
      self.identifier = [NSString stringWithFormat:@"%@ %@", [aRequest HTTPMethod], [aRequest URL]];
    } else return TRUE; // Should md5 the HTTP body ?
  } else {
    self.identifier = [NSString stringWithFormat:@"%@", [aRequest URL]];
  }
  
  if ([_ongoing containsObject:identifier]) return FALSE;
  [_ongoing addObject:identifier];
  return TRUE;
}

- (void)enqueueRequest:(NSURLRequest *)request {
  [queue addOperationWithBlock:^{
#ifdef DEBUG_MCCURLConnection
    NSLog(@"Starting: %@", self);
#endif
    
    BOOL isMainThread = [NSThread isMainThread];
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    
    // Critical section management begin
    __block BOOL shouldReturn = FALSE;
    
    dispatch_sync(_serialQueue, ^{ /* !REF1! it is a synchronous dispatch, we wait for completion... */
      if (self.cancelled) { shouldReturn = TRUE; return; }
      self.started = TRUE;
      
      /* For the same reason don't use a dispatch_sync(_serialQueue, ...) in these callbacks */
      if (onRequest) onRequest(TRUE);
      if (globalOnRequest) globalOnRequest(TRUE);
      
      if (isMainThread) {
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        return;
      }
      
      self.connection = [[[NSURLConnection alloc]initWithRequest:request delegate:self startImmediately:NO]autorelease];
      [connection scheduleInRunLoop:currentRunLoop forMode:NSDefaultRunLoopMode];
      [connection start];
    });
    
    if (shouldReturn) return;
    // End critical section management
        
    while (!(self.finished || self.cancelled)) {
#ifdef DEBUG_MCCURLConnection
      NSLog(@"%p ... ", self);
#endif
      [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
    
    if (onRequest) onRequest(FALSE);
    if (globalOnRequest) globalOnRequest(FALSE);
    
  }];
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"Enqueued: %p", self);
#endif
}

- (NSData *)data { return data; }
- (NSURLResponse *)response { return response; }
- (NSError *)error { return error; }
- (NSInteger)httpStatusCode { return httpStatusCode; }

- (NSString *)description {
  if (isContext) {
    return [NSString stringWithFormat:@"%@ (%p) queue context: %@ (onRequest:%@)", [self class], self, queue == defaultQueue ? @"Default Queue" : queue, onRequest];
  }
  
  NSMutableString *desc = [NSMutableString stringWithFormat:@"%@ (%p) connection\n", [self class], self];
                  [desc appendFormat:@"\tStarted:          %@\n", started ? @"YES" : @"NO"];
                  [desc appendFormat:@"\tQueue:            %@\n", queue == defaultQueue ? @"Default Queue" : queue];
  if (connection) [desc appendFormat:@"\tConnection:       %@\n", connection];
  if (cancelled)   [desc appendFormat:@"\tCanceled:         %@\n", cancelled ? @"YES" : @"NO"];
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

  if (onResponse) onResponse(self, response);
#ifdef DEBUG_MCCURLConnection
  NSLog(@"*** response in %p", self);
#endif
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)chunk {
  if (self.cancelled) return;
  
  if (onData) onData(self, chunk);
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
