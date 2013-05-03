//
//  main.m
//  get
//
//  Created by Thierry Passeron on 29/04/13.
//  Copyright (c) 2013 Monte-Carlo Computing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MCCURLConnection.h"

@interface MCCURLConnection ()
+ (NSArray *)livings;
@end

int main(int argc, const char * argv[])
{

  @autoreleasepool {
    
    {
      NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]];
      __block BOOL finished = FALSE;
      __block int ok = 0;

      for (id<MCCURLConnectionContextProtocol>context in @[[MCCURLConnection class], [MCCURLConnection context]]) {
        NSLog(@"Context: %@", context);
        
        // Onrequest check
        finished = FALSE;
        ok = 0;

        [context setOnRequest:^(MCCURLConnection *c){
          ok++;
          if (c.state == ConnectionStateFinished) {
            finished = TRUE;
          }
        }];
        [context connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *connection) {
          ok++;
        }];
        
        while (!finished) {
          [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
        }
        
        NSCAssert(ok == 3, @"test onRequest failed: %d", ok);
        [context setOnRequest:nil];
        NSLog(@"Onrequest OK");
        
        
        // enforce unique resources check1
        finished = FALSE;
        ok = 0;
        [context setEnforcesUniqueRequestedResource:YES];
        [context connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *connection) {
          if (connection.finishedState != FinishedStateInvalid) {
            ok++;
            finished = TRUE;
          }
        }];
        [context connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *connection) {
          if (connection.finishedState != FinishedStateInvalid) {
            ok++;
            finished = TRUE;
          }
        }];
        
        while (!finished) {
          [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
        }
        
        NSCAssert(ok == 1, @"test enforcement failed: %d", ok);
        NSLog(@"enforcement OK");
        

        // enforce no unique resources check2
        finished = FALSE;
        ok = 0;
        [context setEnforcesUniqueRequestedResource:NO];
        [context connectionWithRequest:[[request copy]autorelease] onFinished:nil];
        [context connectionWithRequest:[[request copy]autorelease] onFinished:nil];
        [context setOnRequest:^(MCCURLConnection *c) {
          if (c.state == ConnectionStateFinished) {
            if (c.finishedState != FinishedStateInvalid) {
              ok++;
            } else NSLog(@"%@", c);
            
            if (ok == 2) {
              finished = TRUE;
            }            
          }
        }];

        while (!finished) {
          [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
        }
        
        NSCAssert(ok == 2, @"test no enforcement failed: %d", ok);
        [context setOnRequest:nil];
        [context setEnforcesUniqueRequestedResource:YES];
        NSLog(@"No enforcement OK");
        
      }
      
      NSLog(@"test0 OK");
    }
    
    
    {
      // Connection in global context
      __block BOOL finished = FALSE;
      __block uint count = 0;
      [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]]
                                    onFinished:^(MCCURLConnection *connection) {
                                      count++;
                                      NSLog(@"Finished: %@", connection);
                                      finished = TRUE;
                                    }];
      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }

      NSCAssert(count == 1, @"failed test");
      NSLog(@"test1 OK");
    }
    

    {
      // Connection in global context with onRequest
      __block BOOL finished = FALSE;
      __block uint count = 0;
      [MCCURLConnection setOnRequest:^(MCCURLConnection *connection) {
        count++;
        finished = (count > 1);
      }];
      [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]]
                                   onFinished:^(MCCURLConnection *connection) {
                                     count++;
                                   }];
      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      NSCAssert(count == 3, @"failed test");
      NSLog(@"test2 OK");
    }
    
    {
      // Connection in custom context with global and context onRequest
      __block BOOL finished = FALSE;
      __block uint count = 0;
      [MCCURLConnection setOnRequest:^(MCCURLConnection *connection) {
        count++;
        finished = (count > 4);
      }];
      
      MCCURLConnection *context = [MCCURLConnection context];

      [context setOnRequest:^(MCCURLConnection *connection) {
        count++;
      }];
      
      [context connectionWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]]
                                   onFinished:^(MCCURLConnection *connection) {
                                     count++;
                                   }];
      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      [MCCURLConnection setOnRequest:nil];
      
      NSCAssert(count == 5, @"failed test");
      NSLog(@"test3 OK");
    }
    

    {
      __block int left = 2;
      __block int resp = 0;
      __block int dat = 0;
      
      MCCURLConnection *_context = [MCCURLConnection context];
      for (id<MCCURLConnectionContextProtocol> context in @[[MCCURLConnection class], _context]) {
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]];
        
        MCCURLConnection *connection = [(MCCURLConnection *)context connection];
        connection.onFinished = ^(MCCURLConnection *c) {
          left--;
        };
        connection.onData = ^(NSData *chunk) {
          dat++;
        };
        connection.onResponse = ^(NSURLResponse *response){
          resp++;
        };
        [connection enqueueRequest:request];
      }
      
      while (left) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      NSCAssert((dat >= 2) && (resp == 2), @"failed test: %d, %d", dat, resp);
      
      NSLog(@"test4 OK");
    }

    {
      // Check cancels with no concurrency
      
      __block BOOL finished = FALSE;
      __block int ok = 0;
      NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]];
      
      NSOperationQueue *queue = [[[NSOperationQueue alloc]init]autorelease];
      queue.maxConcurrentOperationCount = 2;
      [MCCURLConnection setQueue:queue];

      __block int delay = 2;

      // Check immediate cancel

      [[MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
        NSCAssert(c.finishedState == FinishedStateCancelled, @"should have been cancelled 1");
        ok++;
      }]cancel];

      
      // Check wait loop cancel
      MCCURLConnection *connection = [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
        NSCAssert(c.finishedState == FinishedStateCancelled, @"should have been cancelled 2");
        delay = 0; // no more delay
        ok++;
      }];
      
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
        NSLog(@"Cancelling...");
        [connection cancel];
        
        [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
          finished = TRUE;
        }];
      });
      
      
      
      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      [MCCURLConnection setOnRequest:nil];
      
      NSCAssert(ok == 2, @"failed test: %d", ok);
      NSLog(@"test5 OK");
    }

    {
      // Check cancels with concurrency
      NSLog(@"%@", [MCCURLConnection description]);
      
      __block BOOL finished = FALSE;
      __block int ok = 0;
      NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]];
      
      NSOperationQueue *queue = [[[NSOperationQueue alloc]init]autorelease];
      queue.maxConcurrentOperationCount = 3;
      [MCCURLConnection setQueue:queue];
      
      
      // Check wait loop cancel
      MCCURLConnection *connection = [MCCURLConnection connection];
    
      connection.onFinished = ^(MCCURLConnection *c) {
        NSCAssert(c.finishedState == FinishedStateCancelled, @"should have been cancelled: %@", c);
        NSLog(@"Cancelled!");
        ok++;
      };
      
      [connection setOnResponse:^(NSURLResponse *r) {
        // Duplicate request test
        [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
          if (c.finishedState == FinishedStateInvalid) {
            ok++;
          }
        }];
      }];
      
      [connection enqueueRequest:[[request copy]autorelease]];

      
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
        NSLog(@"Cancelling...");
        [connection cancel];
        
        [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
          ok++;
          finished = TRUE;
        }];
      });
      
      
      
      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      [MCCURLConnection setOnRequest:nil];
      
      NSCAssert(ok == 3, @"failed test: %d", ok);
      NSLog(@"test6 OK");
    }
    
    {
      __block BOOL finished = FALSE;
      __block int ok = 0;
      NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:3000"]];
      
      NSOperationQueue *queue = [[[NSOperationQueue alloc]init]autorelease];
      queue.maxConcurrentOperationCount = 2;
      [MCCURLConnection setQueue:queue];
      
      
      __block MCCURLConnection *_connection = [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
        NSCAssert(c.finishedState == FinishedStateCancelled, @"should have been cancelled: %@", c);
        NSLog(@"Cancelled!");
        ok++;
      }];
      
      
      typedef void(^onDataBlock)(NSData*);
      
      onDataBlock(^__block ondata)(MCCURLConnection *) = ^onDataBlock(MCCURLConnection *_c){
        __block MCCURLConnection *mc = _c;
        return [[^(NSData *chunk) {
          NSLog(@"Cancelling: %d", ok);
          [mc cancel];
          
          if (ok == 5) {
            finished = TRUE;
            return;
          }
          
          MCCURLConnection * connection = [MCCURLConnection connectionWithRequest:[[request copy]autorelease] onFinished:^(MCCURLConnection *c) {
            NSCAssert(c.finishedState == FinishedStateCancelled, @"should have been cancelled: %@", c);
            NSLog(@"Cancelled!");
            ok++;
          }];
          connection.onData = ondata(connection);
        }copy]autorelease];
      };
      
      _connection.onData = ondata(_connection);

      while (!finished) {
        [[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];
      }
      
      NSLog(@"test7 OK");
      
    }
    
    
    NSLog(@"All tests passed!");

  }
  
  
  @autoreleasepool {
    while ([(NSArray *)[MCCURLConnection livings]count]) {
      if (![[NSRunLoop currentRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:2.]]) sleep(2);
      NSLog(@"Livings: %@", [MCCURLConnection livings]);
    }
  }

  return 0;
}

