//
//  BWJMultipeerConnectivityController.m
//  BandwithJacker-mac
//
//  Created by Jason Scharff on 9/9/16.
//  Copyright © 2016 Jason Scharff. All rights reserved.
//

#import "BWJMultipeerConnectivityController.h"

#import "MCSession+SessionIdentifier.h"

#import "BWJDownloadRequest.h"

@import MultipeerConnectivity;

static NSString * const kBWJMultipeerConnectivityServiceType = @"bwj-mpc-service";

@interface BWJMultipeerConnectivityController() <MCNearbyServiceBrowserDelegate, MCSessionDelegate, MCBrowserViewControllerDelegate>

@property (nonatomic) MCNearbyServiceBrowser *serviceBrowser;
@property (nonatomic) MCPeerID *peerID;
@property (nonatomic) MCSession *masterSession;
@property (nonatomic) NSMutableDictionary <NSString *, NSMutableDictionary<MCPeerID *, NSURL *>*>*peerFiles;
@property (nonatomic) NSData *endSignal;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *>*numberOfPeersFinished;
@property (nonatomic) NSMutableSet *peers;


@end

@implementation BWJMultipeerConnectivityController

+ (instancetype)sharedMultipeerConnectivityController {
    static dispatch_once_t onceToken;
    static BWJMultipeerConnectivityController *_sharedInstance;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if(self) {
        NSString *computerName = [[NSHost currentHost] localizedName];
        self.peerID = [[MCPeerID alloc]initWithDisplayName:computerName];
        self.masterSession = [[MCSession alloc]initWithPeer:self.peerID
                                     securityIdentity:nil
                                 encryptionPreference:MCEncryptionNone];
        self.masterSession.delegate = self;
        self.serviceBrowser = [[MCNearbyServiceBrowser alloc]initWithPeer:self.peerID
                                                              serviceType:kBWJMultipeerConnectivityServiceType];
        self.serviceBrowser.delegate = self;
    }
    return self;
}

-(MCBrowserViewController *)browserViewController {
    MCBrowserViewController *browserVC = [[MCBrowserViewController alloc]initWithBrowser:self.serviceBrowser
                                                                                 session:self.masterSession];
    browserVC.delegate = self;
    return browserVC;
}

- (void)browser:(MCNearbyServiceBrowser *)browser
      foundPeer:(MCPeerID *)peerID
withDiscoveryInfo:(NSDictionary<NSString *,NSString *> *)info {
    
    
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    if(state == MCSessionStateConnected) {
        [self.peers addObject:peerID];
    } else if (state == MCSessionStateNotConnected) {
        //This is a problem if we are in the middle of downloading.
        //Show some sort of error later.
        if([self.peers containsObject:peerID]) {
            [self.peers removeObject:peerID];
        }
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    //ignore for now.
}

#pragma mark mcsessiondelegate

- (void)session:(MCSession *)session
 didReceiveData:(NSData *)data
       fromPeer:(MCPeerID *)peerID {
    //Run the IO operation on a background thread.
    //Make sure it's the same queue to avoid any mixups in the order of the data.
    if([data isEqualToData:self.endSignal]) {
        NSNumber *numberOfPeersFinished = self.numberOfPeersFinished[session.sessionID];
        if(!numberOfPeersFinished) {
            numberOfPeersFinished = 0;
        } else {
            int newNumberOfPeers = numberOfPeersFinished.intValue + 1;
            numberOfPeersFinished = @(newNumberOfPeers);
        }
        self.numberOfPeersFinished[session.sessionID] = numberOfPeersFinished;
        if(numberOfPeersFinished.intValue == self.peers.count) {
            //We're finished downloading.
            [self mergeFilesForSession:session];
        }
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSURL *pathURL = self.peerFiles[session.sessionID][peerID];
            if(pathURL) {
                NSError *error;
                NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:pathURL error:&error];
                if(error) {
                    NSLog(@"error opening path = %@", error.localizedDescription);
                } else {
                    [fileHandle seekToEndOfFile];
                    //First we need to make sure this is coming in order.
                    [fileHandle writeData:data];
                    [fileHandle closeFile];
                }
            } else {
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *directory = [documentsDirectory stringByAppendingPathComponent:session.sessionID];
                if(![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
                    NSError *error;
                    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                              withIntermediateDirectories:YES
                                                               attributes:nil
                                                                    error:&error];
                    if(error) {
                        NSLog(@"well fuck + %@", error.localizedDescription);
                    }
                }
                NSString *filename = peerID.displayName;
                NSString *loadPath = [directory stringByAppendingPathComponent:filename];
                
                self.peerFiles[session.sessionID][peerID] = [NSURL URLWithString:loadPath];
                [data writeToFile:loadPath atomically:YES];
            }
        });
    }
}


- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {
    //should cat in theory, but client won't use this.
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName
       fromPeer:(MCPeerID *)peerID
   withProgress:(NSProgress *)progress {
    //anything?
}


- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {
    //should cat in theory, but client won't use this.
}


- (void)mergeFilesForSession : (MCSession *)session {
    //TODO
}

- (void)addDownloadRequestOperation:(BWJDownloadRequest *)download {
    MCSession *session = [[MCSession alloc]initWithPeer:self.peerID
                                       securityIdentity:nil
                                   encryptionPreference:MCEncryptionNone];
    session.sessionID = download.serverID;
}

#pragma mark getters
- (NSData *)endSignal {
    if(!_endSignal) {
        NSString *endSignalString = @"DID_FINISH_DOWNLOAD";
        _endSignal = [endSignalString dataUsingEncoding:NSUTF8StringEncoding];
    }
    return _endSignal;
}

#pragma mark MCBrowserDelegate

- (void)browserViewControllerDidFinish:(MCBrowserViewController *)browserViewController {
    dispatch_async(dispatch_get_main_queue(), ^{
        [browserViewController.presentingViewController dismissViewController:browserViewController];
    });
}

- (void)browserViewControllerWasCancelled:(MCBrowserViewController *)browserViewController {
    dispatch_async(dispatch_get_main_queue(), ^{
        [browserViewController.presentingViewController dismissViewController:browserViewController];
    });
}

@end
