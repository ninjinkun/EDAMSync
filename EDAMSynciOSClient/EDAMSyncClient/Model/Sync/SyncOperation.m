//
//  SyncOperation.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/21/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "SyncOperation.h"
#import "CoreDataManager.h"
#import "ClientStateManager.h"
#import "NSDate+MySQL.h"

@implementation SyncOperation {
    NSManagedObjectContext *_managedObjectContext; // 別スレッドでManagedObjectContextを持つ
}

-(void)main {
    NSLog(@"start");
    self.progress = 0.1;
    _managedObjectContext = [[CoreDataManager sharedManager] newManagedObjectContext];
    
    // サーバーからState情報を取得
    NSMutableString *stateUrl = [NSMutableString stringWithFormat:@"%@/server/api/state", EDAM_SERVER_HOST];
    NSInteger afterUSN = [ClientStateManager sharedmanager].lastUpdatedCount;
    if (afterUSN) {
        [stateUrl appendFormat:@"?after_usn=%d", afterUSN];
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:stateUrl]];
    NSURLResponse *res;
    NSError *error;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&error];
    if (!jsonData) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    NSDate *fullSyncBefore = [state objectForKey:@"full_sync_before"] ? [NSDate dateWithTimeIntervalSince1970:[[state objectForKey:@"full_sync_before"] integerValue]] : nil ;
    NSInteger serverUpdateCount = [state objectForKey:@"update_count"] ? [[state objectForKey:@"update_count"] integerValue] : 0;
    
    NSDate *lastSyncTime = [ClientStateManager sharedmanager].lastSyncTime;
    NSInteger lastUpdatedCount = [ClientStateManager sharedmanager].lastUpdatedCount;
    
    self.progress = 0.2;
    
    // completionブロックで返す結果の配列
    NSArray *syncronizedEntries = @[];
    NSArray *conflictedEntries = @[];
    
    if (self.isCancelled) return;
    
    NSLog(@"before %@", fullSyncBefore);
    NSLog(@"last %@", lastSyncTime);
    
    // fullSyncbefore > lastSyncTime
    if ([fullSyncBefore earlierDate:lastSyncTime] == lastSyncTime) {
        // Full Sync
        NSLog(@"Full Sync");
        NSDictionary *syncRes = [self sync:0];
        
        self.progress = 0.5;
        
        NSArray *willSyncEntries = [syncRes objectForKey:@"will_sync_entries"];
        conflictedEntries = [syncRes objectForKey:@"conflicted_entries"];
        
        NSDictionary *sendChangesRes = [self sendChanges:willSyncEntries lastUpdateCount:lastUpdatedCount];
        
        self.progress = 0.8;
        
        NSMutableArray *_conflictedEntries = [conflictedEntries mutableCopy];
        [_conflictedEntries addObjectsFromArray:[sendChangesRes objectForKey:@"conflicted_entries"]];
        conflictedEntries = [_conflictedEntries copy];
        syncronizedEntries = [sendChangesRes objectForKey:@"syncronized_entries"];
    }
    else if ([lastSyncTime isEqualToDate:fullSyncBefore]) {
        // Send Changes
        NSLog(@"Send changes");
        
        // dirtyなものだけ送信する
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(dirty == YES)"];
        NSError *fetchError;
        NSArray *clientEntries = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
        
        self.progress = 0.5;
        
        NSDictionary *sendChangesRes = [self sendChanges:clientEntries lastUpdateCount:lastUpdatedCount];
        NSMutableArray *_conflictedEntries = [conflictedEntries mutableCopy];
        [_conflictedEntries addObjectsFromArray:[sendChangesRes objectForKey:@"conflicted_entries"]];
        conflictedEntries = [_conflictedEntries copy];
        syncronizedEntries = [sendChangesRes objectForKey:@"syncronized_entries"];
        
        self.progress = 0.8;
    }
    else {
        // incremental sync
        NSLog(@"Incremental Sync");
        NSDictionary *syncRes = [self sync:afterUSN];
        self.progress = 0.5;
        
        NSArray *willSyncEntries = [syncRes objectForKey:@"will_sync_entries"];
        conflictedEntries = [syncRes objectForKey:@"conflicted_entries"];
        
        NSDictionary *sendChangesRes = [self sendChanges:willSyncEntries lastUpdateCount:lastUpdatedCount];
        
        NSMutableArray *_conflictedEntries = [conflictedEntries mutableCopy];
        [_conflictedEntries addObjectsFromArray:[sendChangesRes objectForKey:@"conflicted_entries"]];
        conflictedEntries = [_conflictedEntries copy];
        syncronizedEntries = [sendChangesRes objectForKey:@"syncronized_entries"];
        
        self.progress = 0.8;
    }
    if (self.isCancelled) return;
    
    self.progress = 1.0;
    
    // to hash
    NSMutableArray *syncronizedEntriesResult = [@[] mutableCopy];
    for (NSManagedObject *entry in syncronizedEntries) {
        [syncronizedEntriesResult addObject:[entry dictionaryWithValuesForKeys:[[[entry entity] attributesByName] allKeys]]];
    }
    NSMutableArray *conflictedEntriesResult = [@[] mutableCopy];
    for (NSDictionary *dict in conflictedEntries) {
        NSManagedObject *clientEntry = [dict objectForKey:@"client"];
        NSManagedObject *serverEntry = [dict objectForKey:@"server"];
        [conflictedEntriesResult addObject:@{
         @"client" : [clientEntry dictionaryWithValuesForKeys:[[[clientEntry entity] attributesByName] allKeys]],
         @"server" : serverEntry,
         }];
    }
    
    if (_completion) _completion(syncronizedEntriesResult, conflictedEntriesResult, nil);
}

-(NSDictionary *)sync:(NSInteger)afterUSN {
    // エントリー情報を取得
    NSMutableString *entriesUrl = [[NSString stringWithFormat:@"%@/server/api/entries", EDAM_SERVER_HOST] mutableCopy];
    if (afterUSN) {
        [entriesUrl appendFormat:@"?after_usn=%d", afterUSN];
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:entriesUrl]];
    NSURLResponse *res;
    NSError *requestError;
    NSError *jsonError;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&requestError];
    if (!jsonData) {
        NSLog(@"Unresolved error %@, %@", requestError, [requestError userInfo]);
    }
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    NSArray *serverEntries = [json objectForKey:@"entries"];
    
    NSInteger serverUpdateCount = [[json objectForKey:@"server_update_count"] integerValue];
    NSDate *severCurrentTime = [NSDate dateWithTimeIntervalSince1970:[[json objectForKey:@"server_current_time"] integerValue]];
    
    // サーバーのUUIDと同じものもしくはdirtyフラグが立っているものをCoreDataから取得
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(uuid IN %@ OR dirty == YES)", [serverEntries valueForKeyPath:@"uuid"]];
    NSError *fetchError;
    NSArray *clientEntries = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
    
    NSDictionary *clientUUIDMap = [NSDictionary dictionaryWithObjects:clientEntries forKeys:[clientEntries valueForKeyPath:@"uuid"]];
    NSDictionary *serverUUIDMap = [NSDictionary dictionaryWithObjects:serverEntries forKeys:[serverEntries valueForKeyPath:@"uuid"]];
    
    NSSet *clientUUIDSet = [NSSet setWithArray:[clientEntries valueForKeyPath:@"uuid"]];
    NSSet *serverUUIDSet = [NSSet setWithArray:[serverEntries valueForKeyPath:@"uuid"]];
    
    // サーバーのみのエントリー
    NSMutableSet *willSaveUUIDSet = [serverUUIDSet mutableCopy];
    [willSaveUUIDSet minusSet:clientUUIDSet];
    
    // クライアントのみのエントリー
    NSMutableSet *clientOnlyUUIDSet = [clientUUIDSet mutableCopy];
    [clientOnlyUUIDSet minusSet:serverUUIDSet];
    
    // クライアントとローカルの両方にエントリがあってかつdirtyフラグが立っている
    NSMutableSet *needsResolveUUIDSet = [clientUUIDSet mutableCopy];
    [needsResolveUUIDSet intersectSet:serverUUIDSet];
    
    
    NSMutableArray *willSycnEntries = [[clientEntries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(uuid IN %@ AND dirty == YES)", clientOnlyUUIDSet]] mutableCopy];
    NSMutableArray *willRemoveEntries = [[clientEntries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(uuid IN %@ AND dirty == NO)", clientOnlyUUIDSet]] mutableCopy];
    
    NSMutableArray *conflictedEntries = [@[] mutableCopy];
    NSMutableArray *willSaveEntries = [[serverEntries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"uuid IN %@", willSaveUUIDSet]] mutableCopy];
    
    for (NSString *uuid in needsResolveUUIDSet) {
        id clientEntry = [clientUUIDMap objectForKey:uuid];
        id serverEntry = [serverUUIDMap objectForKey:uuid];
        if ([[serverEntry valueForKeyPath:@"usn"] integerValue] == [[clientEntry valueForKeyPath:@"usn"] integerValue]) {
            if ([[clientEntry valueForKeyPath:@"dirty"] boolValue]) {
                [willSycnEntries addObject:clientEntry];
            }
        }
        else if ([[serverEntry valueForKeyPath:@"usn"] integerValue] > [[clientEntry valueForKeyPath:@"usn"] integerValue]) {
            if ([[clientEntry valueForKeyPath:@"dirty"] boolValue]) {
                [conflictedEntries addObject:@{
                 @"client": clientEntry,
                 @"server": serverEntry,
                 }];
            }
            else {
                [willSaveEntries addObject:serverEntry];
            }
        }
    }
    
    for (NSDictionary *serverEntry in willSaveEntries) {
        NSManagedObject * clientEntry = [clientUUIDMap objectForKey:[serverEntry valueForKeyPath:@"uuid"]];
        if (!clientEntry) {
            clientEntry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
            [clientEntry setValue:[serverEntry valueForKey:@"uuid"] forKey:@"uuid"];
            [clientEntry setValue:[NSDate dateWithMySQLDateTime:[serverEntry valueForKeyPath:@"created_at"]] forKey:@"created_at"];
        }
        [clientEntry setValue:[serverEntry valueForKey:@"body"] forKey:@"body"];
        [clientEntry setValue:[serverEntry valueForKey:@"usn"] forKey:@"usn"];
        [clientEntry setValue:@(NO) forKey:@"dirty"];
        [clientEntry setValue:[NSDate dateWithMySQLDateTime:[serverEntry valueForKey:@"updated_at"]] forKey:@"updated_at"];
    }
    for (NSManagedObject *clientEntry in willRemoveEntries) {
        [_managedObjectContext deleteObject:clientEntry];
    }
    
    NSError *saveError;
    if (![_managedObjectContext save:&saveError]) {
        NSLog(@"Unresolved error %@, %@", saveError, [saveError userInfo]);
        abort();
    }
    
    //    [ClientStateManager sharedmanager].lastUpdatedCount = serverUpdateCount;
    //    [ClientStateManager sharedmanager].lastSyncTime = severCurrentTime;
    
    return @{
    @"will_sync_entries"  : willSycnEntries,
    @"conflicted_entries" : conflictedEntries,
    };
}


-(NSDictionary *)sendChanges:(NSArray *)willSyncEntries lastUpdateCount:(NSInteger)lastUpdateCount {
    NSString *syncUrl = [NSString stringWithFormat:@"%@/server/api/sync", EDAM_SERVER_HOST];
    
    // リクエスト用のデータを組み立てる
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    NSMutableArray *conflictedEntries = [@[] mutableCopy];
    NSMutableArray *syncronizedEntries = [@[] mutableCopy];
    for (NSManagedObject *entry in willSyncEntries) {
        NSBlockOperation *op = [[NSBlockOperation alloc] init];
        [op addExecutionBlock:^{
            NSError *jsonError;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{
                                @"entry": @{
                                    @"uuid"       : [entry valueForKey:@"uuid"],
                                    @"body"       : [entry valueForKey:@"body"],
                                    @"usn"        : [entry valueForKey:@"usn"],
                                    @"dirty"      : [entry valueForKey:@"dirty"],
                                    @"created_at" : [[entry valueForKey:@"created_at"] MySQLDateTime],
                                    @"updated_at" : [[entry valueForKey:@"updated_at"] MySQLDateTime],
                                }
            } options:0 error:&jsonError];
            NSMutableData * body = [[@"client=iphone&entry=" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [body appendData:jsonData];
            
            // POST Request
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:syncUrl]];
            [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"content-type"];
            req.HTTPMethod = @"POST";
            req.HTTPBody = body;
            
            NSHTTPURLResponse *res;
            NSError *requestError;
            NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&requestError];
            if (!data) {
                NSLog(@"Unresolved error %@, %@", requestError, [requestError userInfo]);
                abort();
            }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            NSInteger severUpdateCount = [[json objectForKey:@"server_update_count"] ?: @0 integerValue];
            NSDate *severCurrentTime = [NSDate dateWithTimeIntervalSince1970:[[json objectForKey:@"server_current_time"] integerValue]];
            
            NSDictionary *serverEntry = [json objectForKey:@"entry"];
            NSDictionary *conflictedEntry;
            
            if ([res statusCode] == 409) {
                conflictedEntry = [json objectForKey:@"conflicted_entry"];
            }
            
            // サーバーのエントリと同一のUUIDのものをCoreDataから取得
            NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(uuid = %@)", [serverEntry valueForKey:@"uuid"]];
            fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
            NSError *fetchError;
            NSManagedObject *clientEntry = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError][0];
            
            
            if ([[serverEntry objectForKey:@"usn"] integerValue] == lastUpdateCount + 1) {
                // TODO: last update count を更新する
            }
            else if ([[serverEntry objectForKey:@"usn"] integerValue] > lastUpdateCount + 1) {
                // TODO: incremental syncを実行する
            }
            [clientEntry setValue:[serverEntry valueForKey:@"body"] forKey:@"body"];
            [clientEntry setValue:[serverEntry valueForKey:@"usn"] forKey:@"usn"];
            [clientEntry setValue:@(NO) forKey:@"dirty"];
            [clientEntry setValue:[NSDate dateWithMySQLDateTime:[serverEntry valueForKey:@"updated_at"]] forKey:@"updated_at"];
            [syncronizedEntries addObject:clientEntry];
            
            
            NSError *saveError;
            if (![_managedObjectContext save:&saveError]) {
                NSLog(@"Unresolved error %@, %@", saveError, [saveError userInfo]);
                abort();
            }
            
            [ClientStateManager sharedmanager].lastUpdatedCount = severUpdateCount;
            [ClientStateManager sharedmanager].lastSyncTime = severCurrentTime;
            
        }];
        [queue addOperation:op];
    }
    [queue waitUntilAllOperationsAreFinished];
    
    return @{
    @"conflicted_entries"  : conflictedEntries,
    @"syncronized_entries" : syncronizedEntries,
    };
}


#pragma - mark UpdateDelegate
-(void)setProgress:(float)progress {
    _progress = progress;
    if ([_progressDelegate respondsToSelector:@selector(updateProgress:)]) {
        [_progressDelegate updateProgress:progress];
    }
}

@end
