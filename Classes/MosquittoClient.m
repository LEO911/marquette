//
//  MosquittoClient.m
//
//  Copyright 2012 Nicholas Humfrey. All rights reserved.
//

#import "MosquittoClient.h"
#import "mosquitto.h"

@implementation MosquittoClient

@synthesize host;
@synthesize port;
@synthesize keepAlive;
@synthesize cleanSession;
@synthesize delegate;


static void on_connect(void *ptr, int rc)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didConnect:)])
        [[self delegate] didConnect:(NSUInteger)rc];
}

static void on_disconnect(void *ptr)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didDisconnect)])
        [[self delegate] didDisconnect];
}

static void on_publish(void *ptr, uint16_t message_id)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didPublish:)])
        [[self delegate] didPublish:(NSUInteger)message_id];
}

static void on_message(void *ptr, const struct mosquitto_message *message)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	NSString *topic = [NSString stringWithUTF8String: message->topic];
	NSString *payload = [NSString stringWithCharacters:(const unichar *)message->payload
												 length:message->payloadlen];

	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didReceiveMessage:topic:)])
        [[self delegate] didReceiveMessage:payload topic:topic];
}

static void on_subscribe(void *ptr, uint16_t message_id, int qos_count, const uint8_t *granted_qos)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didSubscribe:grantedQos:)])
        [[self delegate] didSubscribe:message_id grantedQos:nil];
	// FIXME: implement this
}

static void on_unsubscribe(void *ptr, uint16_t message_id)
{
	MosquittoClient* self = (MosquittoClient*)ptr;
	// FIXME: cache respondsToSelector
	if ([[self delegate] respondsToSelector:@selector(didUnsubscribe:)])
        [[self delegate] didUnsubscribe:message_id];
}


// Initialize is called just before the first object is allocated
+ (void)initialize {
    mosquitto_lib_init();
}

+ (NSString*)version {
    int major, minor, revision;
    mosquitto_lib_version(&major, &minor, &revision);
    return [NSString stringWithFormat:@"%d.%d.%d", major, minor, revision];
}

- (MosquittoClient*) initWithClientId: (NSString*) clientId {
    if ((self = [super init])) {
        const char* cstrClientId = [clientId cStringUsingEncoding:NSUTF8StringEncoding];
        [self setHost: nil];
        [self setPort: 1883];
        [self setKeepAlive: 30];
        [self setCleanSession: YES];

        mosq = mosquitto_new(cstrClientId, self);
        mosquitto_connect_callback_set(mosq, on_connect);
        mosquitto_disconnect_callback_set(mosq, on_disconnect);
        mosquitto_publish_callback_set(mosq, on_publish);
        mosquitto_message_callback_set(mosq, on_message);
        mosquitto_subscribe_callback_set(mosq, on_subscribe);
        mosquitto_unsubscribe_callback_set(mosq, on_unsubscribe);
        timer = nil;
    }
    return self;
}

- (void) setLogPriorities: (int)priorities destinations:(int)destinations {
    mosquitto_log_init(mosq, priorities, destinations);
}

- (void) connect {
    const char* cstrHost = [host cStringUsingEncoding:NSASCIIStringEncoding];

    mosquitto_connect(mosq, cstrHost, port, keepAlive, cleanSession);

    // Setup timer to handle network events
    // FIXME: better way to do this - hook into iOS Run Loop select() ?
    // or run in seperate thread?
    timer = [NSTimer scheduledTimerWithTimeInterval:0.01 // 10ms
                                             target:self
                                           selector:@selector(loop:)
                                           userInfo:nil
                                            repeats:YES];
}

- (void) reconnect {
    mosquitto_reconnect(mosq);
}

- (void) disconnect {
    mosquitto_disconnect(mosq);
}

- (void) loop: (NSTimer *)timer {
    mosquitto_loop(mosq, 0);
}

// FIXME: add QoS parameter?
- (void)publishString: (NSString *)payload toTopic:(NSString *)topic retain:(BOOL)retain {
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
    const uint8_t* cstrPayload = (const uint8_t*)[payload cStringUsingEncoding:NSUTF8StringEncoding];
    mosquitto_publish(mosq, NULL, cstrTopic, [payload length], cstrPayload, 0, retain);
}

- (void)subscribe: (NSString *)topic {
	[self subscribe:topic withQos:0];
}

- (void)subscribe: (NSString *)topic withQos:(NSUInteger)qos {
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
	mosquitto_subscribe(mosq, NULL, cstrTopic, qos);
}

- (void)unsubscribe: (NSString *)topic {
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
	mosquitto_unsubscribe(mosq, NULL, cstrTopic);
}


- (void) setMessageRetry: (NSUInteger)seconds
{
	mosquitto_message_retry_set(mosq, (unsigned int)seconds);
}

- (void) dealloc {
    if (mosq) {
        mosquitto_destroy(mosq);
        mosq = NULL;
    }

    if (timer) {
        [timer invalidate];
        timer = nil;
    }

    [super dealloc];
}

// FIXME: how and when to call mosquitto_lib_cleanup() ?

@end
