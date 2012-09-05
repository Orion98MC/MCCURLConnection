== Description

MCCURLConnection is a Very Lightweight Queued NSURLConnection with Callback Blocks.

Since MCCURLConnection uses NSOperationQueue to control connections flow you may:

* Control connections' concurrency
* Suspend / resume custom queues
* Cancel ongoing or enqueued connections

== Usage

=== With no queue context

```objective-c
[MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL]
                             onResponse:^(NSURLResponse *response) { ... }
                                 onData:^(NSData *chunk) { ... }
                             onFinished:^(NSError *error, NSInteger status) { ... }];
```

The above example will run the connection callbacks on the main thread.

=== with a queue context

First, let's create a custom queue:

```objective-c
NSOperationQueue *queue = [[[NSOperationQueue alloc] init]autorelease];
queue.maxConcurrentOperationCount = 2;
```

This queue allows 2 concurrent operations.

Now, create the queue context:

```objective-c
 MCCURLConnection *context = [MCCURLConnection contextWithQueue:queue onRequest:nil];
```

Then, submit multiple connections to this queue context:

```objective-c
[context connectionWithRequest:[NSURLRequest requestWithURL:myURL1]
                    onResponse:^(NSURLResponse *response) { ... }
                        onData:^(NSData *chunk) { ... }
                    onFinished:^(NSError *error, NSInteger status) { ... }];

etc...
```

The connection callbacks will run in a custom thread.

At any moment you may suspend / resume the queues or cancel a connection:

```objective-c
MCCURLConnection *connection = [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL1] onResponse:nil onData:nil onFinished:nil];

...

[connection cancel];
```

== Extending

Since the interface of MCCURLConnection is nearly as sparse as NSURLConnection, you may find useful to extend it with custom constructor or add delegate methods. 

You may subclass MCCURLConnection but I think that the best way to extend it would be to add a category.
