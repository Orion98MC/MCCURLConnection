//
//  MCCURLConnection.m
//  MCCHTTPDownloaderDemo
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
@property (copy, nonatomic) void(^onResponse)(NSURLResponse *);
@property (copy, nonatomic) void(^onData)(NSData *);
@property (copy, nonatomic) void(^onFinished)(NSError *, NSInteger status);

@property (assign, nonatomic) NSInteger httpStatusCode;
@property (assign, atomic) BOOL finished;
@property (assign, atomic) BOOL canceled;
@property (assign, atomic) BOOL started;
@property (assign, nonatomic) BOOL isContext;
@end

@implementation MCCURLConnection
@synthesize connection, onRequest, onResponse, onData, onFinished, httpStatusCode, queue, finished, canceled, identifier, started, isContext;


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

static id <NSURLConnectionDelegate> _authenticationDelegate = nil;
+ (void)setAuthenticationDelegate:(id<NSURLConnectionDelegate>)authDelegate {
  _authenticationDelegate = authDelegate;
}


#pragma mark init/dealloc

- (id)init {
  if (!(self = [super init])) return nil;
  
  self.started = FALSE;
  self.finished = FALSE;
  self.canceled = FALSE;
  self.isContext = FALSE;
  self.queue = [NSOperationQueue mainQueue];
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"init: %p", self);
#endif
  
  return self;
}

- (id)initWithRequest:(NSURLRequest *)request
           onResponse:(void(^)(NSURLResponse *response))onResponseCallback
               onData:(void(^)(NSData *data))onDataCallback
           onFinished:(void(^)(NSError *error, NSInteger status))onFinishedCallback {
  if (!(self = [self init])) return nil;
  
  if (![self setOngoingRequest:request] && _unique) {
    [self autorelease];
    return nil;
  }
  
  __block typeof(self) __self = self;
  self.onResponse = onResponseCallback;
  self.onData = onDataCallback;
  self.onFinished = ^(NSError *error, NSInteger status){ __self.finished = TRUE; onFinishedCallback(error, status); };
  
  return self;
}

- (void)dealloc {
#ifdef DEBUG_MCCURLConnection
  NSLog(@"dealloc: %@", self);
#endif
  if (_ongoing && identifier) [_ongoing removeObject:identifier];
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
                 onResponse:(void(^)(NSURLResponse *response))onResponseCallback
                     onData:(void(^)(NSData *data))onDataCallback
                 onFinished:(void(^)(NSError *error, NSInteger status))onFinishedCallback {
  
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
                 onResponse:(void(^)(NSURLResponse *response))onResponseCallback
                     onData:(void(^)(NSData *data))onDataCallback
                 onFinished:(void(^)(NSError *error, NSInteger status))onFinishedCallback {
  
  NSAssert(isContext == TRUE, @"Not a context");
  
  MCCURLConnection *c = [[[self class]alloc]initWithRequest:request onResponse:onResponseCallback onData:onDataCallback onFinished:onFinishedCallback];
  
  // Inherit context
  c.queue = queue;
  if (onRequest) c.onRequest = ^(BOOL flag){ onRequest(flag); };
    
  [c enqueueRequest:request];
  
  return [c autorelease];
}

- (void)cancel {
  canceled = TRUE;
  if (started) {
    [connection cancel];
    if (onRequest) onRequest(FALSE);
    if (globalOnRequest) globalOnRequest(FALSE);
  }
}


#pragma mark tool methods

static NSMutableSet *_ongoing = nil;
- (BOOL)setOngoingRequest:(NSURLRequest *)aRequest {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _ongoing = [[NSMutableSet alloc]init];
  });
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
#ifdef DEBUG_MCCURLConnection
  __block typeof(self) __self = self;
#endif
  
  [queue addOperationWithBlock:^{
#ifdef DEBUG_MCCURLConnection
    NSLog(@"Starting: %@", __self); // Let's not retain self for the debug log
#endif
    if (canceled) return;
    if (onRequest) onRequest(TRUE);
    if (globalOnRequest) globalOnRequest(TRUE);
    
    self.started = TRUE;
    
    if ([NSThread isMainThread]) {
      self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
      return;
    }
    
    self.connection = [[[NSURLConnection alloc]initWithRequest:request delegate:self startImmediately:NO]autorelease];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [connection start];
    
    while (!(finished || canceled)) {
#ifdef DEBUG_MCCURLConnection
      NSLog(@"%p ... ", __self);
#endif
      [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
  }];
  
#ifdef DEBUG_MCCURLConnection
  NSLog(@"Enqueued: %@", self);
#endif
}

- (NSString *)description {
  if (isContext) {
    return [NSString stringWithFormat:@"%@ (%p) queue context: %@ (onRequest:%@)", [self class], self, queue == [NSOperationQueue mainQueue] ? @"Main Queue" : queue, onRequest];
  }
  
  NSMutableString *desc = [NSMutableString stringWithFormat:@"%@ (%p) connection\n", [self class], self];
                  [desc appendFormat:@"\tStarted:          %@\n", started ? @"YES" : @"NO"];
                  [desc appendFormat:@"\tQueue:            %@\n", queue == [NSOperationQueue mainQueue] ? @"Main Queue" : queue];
  if (connection) [desc appendFormat:@"\tConnection:       %@\n", connection];
  if (canceled)   [desc appendFormat:@"\tCanceled:         %@\n", canceled ? @"YES" : @"NO"];
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

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    httpStatusCode = [(NSHTTPURLResponse*)response statusCode];
  }
  if (onResponse) onResponse(response);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)chunk {
  if (onData) onData(chunk);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection {
  if (onFinished) onFinished(nil, httpStatusCode);
  if (onRequest) onRequest(FALSE);
  if (globalOnRequest) globalOnRequest(FALSE);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  if (onFinished) onFinished(error, httpStatusCode);
  if (onRequest) onRequest(FALSE);
  if (globalOnRequest) globalOnRequest(FALSE);
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
