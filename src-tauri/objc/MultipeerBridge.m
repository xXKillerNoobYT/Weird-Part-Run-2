/**
 * MultipeerBridge.m — Apple Multipeer Connectivity wrapper.
 *
 * Implements a global singleton (WPMultipeerManager) that handles:
 * - MCNearbyServiceAdvertiser: advertises this device with company_id in discovery info
 * - MCNearbyServiceBrowser: discovers peers advertising the same service type
 * - MCSession: manages connections and data transfer
 *
 * Peer filtering: Only same-company peers are accepted (company_id must match).
 * Auto-invite: When a same-company peer is discovered, we automatically invite them.
 * Auto-accept: When a same-company peer invites us, we automatically accept.
 *
 * Threading: All state mutations happen on a serial dispatch queue (_syncQueue).
 * Delegate callbacks from MCSession/Browser/Advertiser are dispatched to this queue.
 */

#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>
#include "MultipeerBridge.h"

// Service type: 1-15 chars, lowercase ASCII + hyphens only
static NSString *const kServiceType = @"wiredpart-sync";

// Discovery info keys sent with advertising
static NSString *const kKeyDeviceId   = @"device_id";
static NSString *const kKeyDeviceName = @"device_name";
static NSString *const kKeyCompanyId  = @"company_id";

// ── Peer State Enum ─────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, WPPeerState) {
    WPPeerStateFound      = 0,
    WPPeerStateConnecting = 1,
    WPPeerStateConnected  = 2,
};

// ── Discovered Peer Info ────────────────────────────────────────────

@interface WPPeerInfo : NSObject
@property (nonatomic, copy)   NSString *deviceId;
@property (nonatomic, copy)   NSString *deviceName;
@property (nonatomic, copy)   NSString *companyId;
@property (nonatomic, assign) WPPeerState state;
@property (nonatomic, strong) MCPeerID *mcPeerId;
@end

@implementation WPPeerInfo
@end

// ── Received Message ────────────────────────────────────────────────

@interface WPReceivedMessage : NSObject
@property (nonatomic, copy)   NSString *fromDeviceId;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, copy)   NSString *receivedAt;
@end

@implementation WPReceivedMessage
@end

// ── Manager ─────────────────────────────────────────────────────────

@interface WPMultipeerManager : NSObject <
    MCSessionDelegate,
    MCNearbyServiceBrowserDelegate,
    MCNearbyServiceAdvertiserDelegate
>

@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *companyId;
@property (nonatomic, assign) BOOL running;

@property (nonatomic, strong) MCPeerID *localPeerId;
@property (nonatomic, strong) MCSession *session;
@property (nonatomic, strong) MCNearbyServiceBrowser *browser;
@property (nonatomic, strong) MCNearbyServiceAdvertiser *advertiser;

// device_id → WPPeerInfo
@property (nonatomic, strong) NSMutableDictionary<NSString *, WPPeerInfo *> *peers;

// Receive queue (FIFO)
@property (nonatomic, strong) NSMutableArray<WPReceivedMessage *> *receiveQueue;

// Serial queue for thread safety
@property (nonatomic, strong) dispatch_queue_t syncQueue;

@end

@implementation WPMultipeerManager

+ (instancetype)shared {
    static WPMultipeerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WPMultipeerManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _peers = [NSMutableDictionary new];
        _receiveQueue = [NSMutableArray new];
        _syncQueue = dispatch_queue_create("com.wiredpart.multipeer.sync", DISPATCH_QUEUE_SERIAL);
        _running = NO;
    }
    return self;
}

- (BOOL)initWithDeviceId:(NSString *)deviceId
              deviceName:(NSString *)deviceName
               companyId:(NSString *)companyId {
    __block BOOL success = NO;
    dispatch_sync(_syncQueue, ^{
        self.deviceId = deviceId;
        self.deviceName = deviceName;
        self.companyId = companyId;

        // MCPeerID display name must be 1-63 chars. Use device name.
        NSString *displayName = deviceName;
        if (displayName.length > 63) {
            displayName = [displayName substringToIndex:63];
        }
        if (displayName.length == 0) {
            displayName = @"WiredPart";
        }

        self.localPeerId = [[MCPeerID alloc] initWithDisplayName:displayName];

        // Create session
        self.session = [[MCSession alloc] initWithPeer:self.localPeerId
                                      securityIdentity:nil
                                  encryptionPreference:MCEncryptionRequired];
        self.session.delegate = self;

        success = YES;
    });
    return success;
}

- (BOOL)start {
    __block BOOL success = NO;
    dispatch_sync(_syncQueue, ^{
        if (!self.localPeerId || self.running) return;

        // Discovery info: sent to peers on discovery so they can filter by company
        NSDictionary *discoveryInfo = @{
            kKeyDeviceId:   self.deviceId,
            kKeyDeviceName: self.deviceName,
            kKeyCompanyId:  self.companyId,
        };

        // Start advertising
        self.advertiser = [[MCNearbyServiceAdvertiser alloc]
            initWithPeer:self.localPeerId
           discoveryInfo:discoveryInfo
             serviceType:kServiceType];
        self.advertiser.delegate = self;
        [self.advertiser startAdvertisingPeer];

        // Start browsing
        self.browser = [[MCNearbyServiceBrowser alloc]
            initWithPeer:self.localPeerId
             serviceType:kServiceType];
        self.browser.delegate = self;
        [self.browser startBrowsingForPeers];

        self.running = YES;
        success = YES;

        NSLog(@"[MultipeerBridge] Started advertising + browsing (company: %@)", self.companyId);
    });
    return success;
}

- (void)stop {
    dispatch_sync(_syncQueue, ^{
        if (self.advertiser) {
            [self.advertiser stopAdvertisingPeer];
            self.advertiser = nil;
        }
        if (self.browser) {
            [self.browser stopBrowsingForPeers];
            self.browser = nil;
        }
        if (self.session) {
            [self.session disconnect];
        }
        [self.peers removeAllObjects];
        self.running = NO;

        NSLog(@"[MultipeerBridge] Stopped");
    });
}

- (void)cleanup {
    [self stop];
    dispatch_sync(_syncQueue, ^{
        [self.receiveQueue removeAllObjects];
        self.session = nil;
        self.localPeerId = nil;
    });
}

// ── MCNearbyServiceBrowserDelegate ─────────────────────────────────

- (void)browser:(MCNearbyServiceBrowser *)browser
      foundPeer:(MCPeerID *)peerID
withDiscoveryInfo:(NSDictionary<NSString *, NSString *> *)info {
    dispatch_async(_syncQueue, ^{
        NSString *peerDeviceId  = info[kKeyDeviceId] ?: @"unknown";
        NSString *peerDeviceName = info[kKeyDeviceName] ?: peerID.displayName;
        NSString *peerCompanyId = info[kKeyCompanyId] ?: @"";

        // Only connect to same-company peers
        if (![peerCompanyId isEqualToString:self.companyId]) {
            NSLog(@"[MultipeerBridge] Ignoring peer %@ (different company: %@)",
                  peerDeviceName, peerCompanyId);
            return;
        }

        // Don't connect to ourselves
        if ([peerDeviceId isEqualToString:self.deviceId]) {
            return;
        }

        NSLog(@"[MultipeerBridge] Found same-company peer: %@ (%@)", peerDeviceName, peerDeviceId);

        // Track the peer
        WPPeerInfo *peerInfo = [[WPPeerInfo alloc] init];
        peerInfo.deviceId   = peerDeviceId;
        peerInfo.deviceName = peerDeviceName;
        peerInfo.companyId  = peerCompanyId;
        peerInfo.state      = WPPeerStateFound;
        peerInfo.mcPeerId   = peerID;
        self.peers[peerDeviceId] = peerInfo;

        // Auto-invite same-company peers
        // Context is a JSON payload with our identity for the receiving side
        NSDictionary *context = @{
            kKeyDeviceId:   self.deviceId,
            kKeyDeviceName: self.deviceName,
            kKeyCompanyId:  self.companyId,
        };
        NSData *contextData = [NSJSONSerialization dataWithJSONObject:context options:0 error:nil];

        peerInfo.state = WPPeerStateConnecting;
        [browser invitePeer:peerID
                  toSession:self.session
                withContext:contextData
                    timeout:30.0];

        NSLog(@"[MultipeerBridge] Invited peer: %@", peerDeviceName);
    });
}

- (void)browser:(MCNearbyServiceBrowser *)browser
       lostPeer:(MCPeerID *)peerID {
    dispatch_async(_syncQueue, ^{
        // Find and remove the peer by MCPeerID
        NSString *keyToRemove = nil;
        for (NSString *key in self.peers) {
            if ([self.peers[key].mcPeerId isEqual:peerID]) {
                keyToRemove = key;
                break;
            }
        }
        if (keyToRemove) {
            NSLog(@"[MultipeerBridge] Lost peer: %@", self.peers[keyToRemove].deviceName);
            [self.peers removeObjectForKey:keyToRemove];
        }
    });
}

- (void)browser:(MCNearbyServiceBrowser *)browser
didNotStartBrowsingForPeers:(NSError *)error {
    NSLog(@"[MultipeerBridge] Failed to start browsing: %@", error.localizedDescription);
}

// ── MCNearbyServiceAdvertiserDelegate ──────────────────────────────

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser
didReceiveInvitationFromPeer:(MCPeerID *)peerID
       withContext:(NSData *)context
 invitationHandler:(void (^)(BOOL, MCSession *))invitationHandler {
    dispatch_async(_syncQueue, ^{
        // Parse the inviter's identity from context
        NSDictionary *info = nil;
        if (context) {
            info = [NSJSONSerialization JSONObjectWithData:context options:0 error:nil];
        }

        NSString *peerCompanyId = info[kKeyCompanyId] ?: @"";

        // Only accept same-company peers
        if ([peerCompanyId isEqualToString:self.companyId]) {
            NSString *peerDeviceId   = info[kKeyDeviceId] ?: @"unknown";
            NSString *peerDeviceName = info[kKeyDeviceName] ?: peerID.displayName;

            NSLog(@"[MultipeerBridge] Accepting invitation from: %@ (%@)",
                  peerDeviceName, peerDeviceId);

            // Track the inviting peer
            WPPeerInfo *peerInfo = self.peers[peerDeviceId];
            if (!peerInfo) {
                peerInfo = [[WPPeerInfo alloc] init];
                peerInfo.deviceId   = peerDeviceId;
                peerInfo.deviceName = peerDeviceName;
                peerInfo.companyId  = peerCompanyId;
                peerInfo.mcPeerId   = peerID;
                self.peers[peerDeviceId] = peerInfo;
            }
            peerInfo.state = WPPeerStateConnecting;

            invitationHandler(YES, self.session);
        } else {
            NSLog(@"[MultipeerBridge] Rejecting invitation from different company: %@", peerCompanyId);
            invitationHandler(NO, nil);
        }
    });
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser
didNotStartAdvertisingPeer:(NSError *)error {
    NSLog(@"[MultipeerBridge] Failed to start advertising: %@", error.localizedDescription);
}

// ── MCSessionDelegate ──────────────────────────────────────────────

- (void)session:(MCSession *)session
           peer:(MCPeerID *)peerID
didChangeState:(MCSessionState)state {
    dispatch_async(_syncQueue, ^{
        // Find the peer by MCPeerID
        WPPeerInfo *found = nil;
        for (NSString *key in self.peers) {
            if ([self.peers[key].mcPeerId isEqual:peerID]) {
                found = self.peers[key];
                break;
            }
        }

        if (!found) {
            // Peer connected but we don't have info yet — create entry
            if (state == MCSessionStateConnected) {
                found = [[WPPeerInfo alloc] init];
                found.deviceId   = peerID.displayName; // fallback
                found.deviceName = peerID.displayName;
                found.companyId  = self.companyId;
                found.mcPeerId   = peerID;
                self.peers[found.deviceId] = found;
            } else {
                return;
            }
        }

        switch (state) {
            case MCSessionStateConnected:
                found.state = WPPeerStateConnected;
                NSLog(@"[MultipeerBridge] Connected to: %@", found.deviceName);
                break;
            case MCSessionStateConnecting:
                found.state = WPPeerStateConnecting;
                NSLog(@"[MultipeerBridge] Connecting to: %@", found.deviceName);
                break;
            case MCSessionStateNotConnected:
                NSLog(@"[MultipeerBridge] Disconnected from: %@", found.deviceName);
                [self.peers removeObjectForKey:found.deviceId];
                break;
        }
    });
}

- (void)session:(MCSession *)session
 didReceiveData:(NSData *)data
       fromPeer:(MCPeerID *)peerID {
    dispatch_async(_syncQueue, ^{
        // Find sender's device_id
        NSString *fromDeviceId = peerID.displayName; // fallback
        for (NSString *key in self.peers) {
            if ([self.peers[key].mcPeerId isEqual:peerID]) {
                fromDeviceId = self.peers[key].deviceId;
                break;
            }
        }

        // Enqueue the message
        WPReceivedMessage *msg = [[WPReceivedMessage alloc] init];
        msg.fromDeviceId = fromDeviceId;
        msg.data = data;

        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        msg.receivedAt = [fmt stringFromDate:[NSDate date]];

        [self.receiveQueue addObject:msg];

        NSLog(@"[MultipeerBridge] Received %lu bytes from %@",
              (unsigned long)data.length, fromDeviceId);
    });
}

// Required delegate methods (unused — we use sendData, not streams/resources)

- (void)session:(MCSession *)session
didReceiveStream:(NSInputStream *)stream
       withName:(NSString *)streamName
       fromPeer:(MCPeerID *)peerID {
    // Not used — we send discrete data packets, not streams
}

- (void)session:(MCSession *)session
didStartReceivingResourceWithName:(NSString *)resourceName
       fromPeer:(MCPeerID *)peerID
   withProgress:(NSProgress *)progress {
    // Not used
}

- (void)session:(MCSession *)session
didFinishReceivingResourceWithName:(NSString *)resourceName
       fromPeer:(MCPeerID *)peerID
          atURL:(NSURL *)localURL
      withError:(NSError *)error {
    // Not used
}

// ── Send Data ──────────────────────────────────────────────────────

- (BOOL)sendData:(NSData *)data toPeerWithDeviceId:(NSString *)peerDeviceId {
    __block BOOL success = NO;
    dispatch_sync(_syncQueue, ^{
        WPPeerInfo *peer = self.peers[peerDeviceId];
        if (!peer || peer.state != WPPeerStateConnected) {
            NSLog(@"[MultipeerBridge] Cannot send — peer %@ not connected", peerDeviceId);
            return;
        }

        NSError *error = nil;
        success = [self.session sendData:data
                                 toPeers:@[peer.mcPeerId]
                                withMode:MCSessionSendDataReliable
                                   error:&error];
        if (!success) {
            NSLog(@"[MultipeerBridge] Send failed: %@", error.localizedDescription);
        }
    });
    return success;
}

// ── JSON Serialization ─────────────────────────────────────────────

- (NSString *)peersAsJson {
    __block NSString *json = @"[]";
    dispatch_sync(_syncQueue, ^{
        NSMutableArray *arr = [NSMutableArray new];
        for (NSString *key in self.peers) {
            WPPeerInfo *p = self.peers[key];
            NSString *stateStr;
            switch (p.state) {
                case WPPeerStateFound:      stateStr = @"found"; break;
                case WPPeerStateConnecting: stateStr = @"connecting"; break;
                case WPPeerStateConnected:  stateStr = @"connected"; break;
            }
            [arr addObject:@{
                @"device_id":   p.deviceId,
                @"device_name": p.deviceName,
                @"company_id":  p.companyId,
                @"state":       stateStr,
            }];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
        if (data) {
            json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    });
    return json;
}

@end

// ── C FFI Functions ────────────────────────────────────────────────

static char *copyNSString(NSString *str) {
    if (!str) return NULL;
    const char *utf8 = [str UTF8String];
    size_t len = strlen(utf8) + 1;
    char *copy = (char *)malloc(len);
    if (copy) memcpy(copy, utf8, len);
    return copy;
}

int wp_multipeer_init(const char *device_id,
                      const char *device_name,
                      const char *company_id) {
    @autoreleasepool {
        NSString *did  = [NSString stringWithUTF8String:device_id];
        NSString *name = [NSString stringWithUTF8String:device_name];
        NSString *cid  = [NSString stringWithUTF8String:company_id];

        BOOL ok = [[WPMultipeerManager shared] initWithDeviceId:did
                                                     deviceName:name
                                                      companyId:cid];
        return ok ? 0 : -1;
    }
}

int wp_multipeer_start(void) {
    @autoreleasepool {
        return [[WPMultipeerManager shared] start] ? 0 : -1;
    }
}

void wp_multipeer_stop(void) {
    @autoreleasepool {
        [[WPMultipeerManager shared] stop];
    }
}

void wp_multipeer_cleanup(void) {
    @autoreleasepool {
        [[WPMultipeerManager shared] cleanup];
    }
}

char *wp_multipeer_get_peers_json(void) {
    @autoreleasepool {
        NSString *json = [[WPMultipeerManager shared] peersAsJson];
        return copyNSString(json);
    }
}

int wp_multipeer_send(const char *peer_device_id,
                      const uint8_t *data,
                      uint32_t len) {
    @autoreleasepool {
        NSString *pid = [NSString stringWithUTF8String:peer_device_id];
        NSData *nsData = [NSData dataWithBytes:data length:len];
        BOOL ok = [[WPMultipeerManager shared] sendData:nsData toPeerWithDeviceId:pid];
        return ok ? 0 : -1;
    }
}

char *wp_multipeer_pop_received(void) {
    @autoreleasepool {
        WPMultipeerManager *mgr = [WPMultipeerManager shared];
        __block WPReceivedMessage *msg = nil;

        dispatch_sync(mgr.syncQueue, ^{
            if (mgr.receiveQueue.count > 0) {
                msg = mgr.receiveQueue[0];
                [mgr.receiveQueue removeObjectAtIndex:0];
            }
        });

        if (!msg) return NULL;

        // Encode data as base64
        NSString *base64 = [msg.data base64EncodedStringWithOptions:0];

        NSDictionary *dict = @{
            @"from_device_id": msg.fromDeviceId,
            @"data":           base64 ?: @"",
            @"received_at":    msg.receivedAt,
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
        if (!jsonData) return NULL;

        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        return copyNSString(json);
    }
}

uint32_t wp_multipeer_receive_count(void) {
    @autoreleasepool {
        WPMultipeerManager *mgr = [WPMultipeerManager shared];
        __block uint32_t count = 0;
        dispatch_sync(mgr.syncQueue, ^{
            count = (uint32_t)mgr.receiveQueue.count;
        });
        return count;
    }
}

bool wp_multipeer_is_running(void) {
    return [WPMultipeerManager shared].running;
}

void wp_multipeer_free_string(char *str) {
    if (str) free(str);
}
