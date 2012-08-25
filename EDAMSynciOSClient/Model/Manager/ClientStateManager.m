//
//  ClientStateManager.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/22/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "ClientStateManager.h"
#define kLastSyncTime @"last_sync_time"
#define kLastUpdatedCount @"last_updated_count"
@implementation ClientStateManager
+(ClientStateManager *)sharedmanager {
    static id manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[ClientStateManager allocWithZone:NULL] init];
    });
    return manager;
}

-(void)setLastSyncTime:(NSDate *)date {
    [[NSUserDefaults standardUserDefaults] setInteger:[date timeIntervalSince1970] forKey:kLastSyncTime];
}

-(NSDate *)lastSyncTime {
    NSInteger fullSyncBefore = [[NSUserDefaults standardUserDefaults] integerForKey:kLastSyncTime];
    return fullSyncBefore ? [NSDate dateWithTimeIntervalSince1970:fullSyncBefore] : nil;
}

-(void)setLastUpdatedCount:(NSInteger)lastUpdatedCount {
    [[NSUserDefaults standardUserDefaults] setInteger:lastUpdatedCount forKey:kLastUpdatedCount];
}

-(NSInteger)lastUpdatedCount {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kLastUpdatedCount];
}

@end
