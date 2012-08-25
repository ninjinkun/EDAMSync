//
//  ClientStateManager.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/22/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ClientStateManager : NSObject
+(ClientStateManager *)sharedmanager;
@property (strong) NSDate *lastSyncTime;
@property NSInteger lastUpdatedCount;
@end
