//
//  SyncOperation.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/21/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^SyncOperationCompletion)(NSArray *synchronizedEntries, NSArray *conflictedEntries, NSError *error) ;

@interface SyncOperation : NSOperation
@property (nonatomic, readonly) float progress;
@property (nonatomic, weak) id progressDelegate;
@property (nonatomic, copy) SyncOperationCompletion completion;
@end

@interface NSObject (SyncOperationUpdateDelegate)
-(void)updateProgress:(float)progress;
@end



