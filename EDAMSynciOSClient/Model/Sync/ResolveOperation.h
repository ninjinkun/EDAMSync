//
//  ResolveOperation.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/24/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef void(^ResolveOperationCompletion)(NSArray *resolvedEntries, NSError *error) ;
@interface ResolveOperation : NSOperation
- (id)initWithConflictedEntries:(NSArray *)conflictedEntries;
@property (nonatomic, copy) ResolveOperationCompletion completion;
@end
