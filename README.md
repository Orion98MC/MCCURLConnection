## Description

MCCURLConnection is a Very Lightweight Queued NSURLConnection with Callback Blocks.

Since MCCURLConnection uses NSOperationQueue to control connections flow, you may:

* Control connections' concurrency
* Suspend / resume custom queues
* Cancel ongoing or enqueued connections

You may set few global settings like:

* An Application-wide Authentication delegate (since authentication is most likely to be an application-wide concern)
* An application-wide onRequest callback, useful for setting the network activity indicator for example
* Set whether the class should forbid ongoing duplicate resource request (Example: forbid multiple enqueued HTTP GET of the same URL)
* A default queue for connections created out of a context

## Usage

### With default queue context 

```objective-c
[MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL]
                             onResponse:^(NSURLResponse *response) { ... }
                                 onData:^(NSData *chunk) { ... }
                             onFinished:^(NSError *error, NSInteger status) { ... }];
```

The above example will use the default queue and run callback blocks in a thread.

### With a custom queue context

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

The connection is enqueued in the context queue and callbacks will run in a custom thread.

At any moment you may suspend / resume the queues or cancel a connection:

```objective-c
MCCURLConnection *connection = [MCCURLConnection connectionWithRequest:[NSURLRequest requestWithURL:myURL1] onResponse:nil onData:nil onFinished:nil];

...

[connection cancel];
```

## Extending

Since the interface of MCCURLConnection is nearly as sparse as NSURLConnection, you may find useful to extend it with custom constructor or add delegate methods. 

You may subclass MCCURLConnection but I think that the best way to extend it would be to add a category.


## Blog post

I made a blog post about this class, you may find it here: http://orion98mc.blogspot.com/2012/09/on-asihttprequest-replacement.html


## License terms

Copyright (c), 2012 Thierry Passeron

The MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
