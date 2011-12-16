#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>
#include <unistd.h>
#include <libgen.h>

static Class API;

@interface SkypeAPI : NSObject
+(BOOL)isSkypeRunning;
+(BOOL)isSkypeAvailable;
+(void)setSkypeDelegate:(NSObject*)aDelegate;
+(NSObject*)skypeDelegate;
+(void)removeSkypeDelegate;

+(void)connect;
+(void)disconnect;

+(NSString*)sendSkypeCommand:(NSString*)aCommandString;
@end

@interface MyDelegate : NSObject <NSStreamDelegate>

@property (nonatomic, assign) NSString* name;
@property (nonatomic, retain) NSInputStream* stream;

-(NSString*)clientApplicationName;

-(void)skypeNotificationReceived:(NSString*)aNotificationString;
-(void)skypeAttachResponse:(unsigned)aAttachResponseCode;
-(void)skypeBecameAvailable:(NSNotification*)aNotification;
-(void)skypeBecameUnavailable:(NSNotification*)aNotification;

-(void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode;
@end

@implementation MyDelegate

@synthesize name, stream = _stream;

-(NSString*)clientApplicationName {
    return self.name;
}

-(void)skypeNotificationReceived:(NSString*)aNotificationString {
    fprintf(stdout, "%s\n", [aNotificationString UTF8String]);
}

-(void)skypeAttachResponse:(unsigned)aAttachResponseCode {
    if (0 == aAttachResponseCode) {
        fprintf(stderr, "failed to attach to skype\n");
        exit(1);
    }
}

-(void)skypeBecameAvailable:(NSNotification*)aNotification {

}

-(void)skypeBecameUnavailable:(NSNotification*)aNotification {
    fprintf(stderr, "skype became unavailable\n");
    exit(2);
}

-(void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    char* line = NULL;
    size_t linecap = 0;
    ssize_t linelen;

    if (eventCode != NSStreamEventHasBytesAvailable) return;

    while ((linelen = getline(&line, &linecap, stdin)) > 0) {
        if (linelen == 1) continue; // == '\n';

        NSString* res =
            (NSString*)[API sendSkypeCommand:[NSString stringWithUTF8String:line]];
        if (res) {
            printf("%s\n", [res UTF8String]);
        }
    }

    [stream close];
    [stream removeFromRunLoop:[NSRunLoop currentRunLoop]
                      forMode:NSDefaultRunLoopMode];

    NSInputStream* input_stream;
    CFStreamCreatePairWithSocket(
        kCFAllocatorDefault, 0, // 0
        (CFReadStreamRef*)&input_stream, NULL
    );
    [input_stream setDelegate:self];
    [input_stream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSDefaultRunLoopMode];
    [input_stream open];

    self.stream = input_stream;
}

@end

int main(int argc, char** argv) {
    int opt;
    NSString* application_name = nil;
    NSString* framework_path = nil;

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // default value
    application_name = [NSString stringWithUTF8String:basename(argv[0])];
    framework_path = @"/Applications/Skype.app/Contents/Frameworks/Skype.framework";

    while ((opt = getopt(argc, argv, "n:f:")) != -1) {
        switch (opt) {
            case 'f':
                framework_path = [NSString stringWithUTF8String:optarg];
                break;
            case 'n':
                application_name = [NSString stringWithUTF8String:optarg];
            default:
                break;
        }
    }
    argc -= optind;
    argv += optind;

    NSBundle* bundle = [NSBundle bundleWithPath:framework_path];
    NSError* e;
    if (bundle && [bundle loadAndReturnError:&e]) {
        API = objc_getClass("SkypeAPI");
        if (!API) {
            fprintf(stderr, "Couldn't find Skype class in framework: %s\n", [framework_path UTF8String]);
            return -1;
        }
    }
    else {
        fprintf(stderr, "Couldn't load framework: %s\n", [framework_path UTF8String]);
    }

    MyDelegate* delegate = [[MyDelegate alloc] init];
    delegate.name = application_name;

    if (![API isSkypeRunning]) {
        fprintf(stderr, "skype is not running\n");
        return 2;
    }

    [API setSkypeDelegate:delegate];
    [API connect];

    NSInputStream* input_stream;
    CFStreamCreatePairWithSocket(
        kCFAllocatorDefault, 0, // stdin
        (CFReadStreamRef*)&input_stream, NULL
    );

    [input_stream setDelegate:delegate];
    [input_stream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSDefaultRunLoopMode];
    [input_stream open];

    delegate.stream = input_stream;

    [[NSRunLoop currentRunLoop] run];

    [pool drain];

    return 0;
}
