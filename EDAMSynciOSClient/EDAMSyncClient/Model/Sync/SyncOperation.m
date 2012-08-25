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
    NSManagedObjectContext *_managedObjectContext;
}

-(void)main {
    NSLog(@"start");
    self.progress = 0.1;
    
    NSMutableString *stateUrl = [NSMutableString stringWithFormat:@"%@/server/api/state", EDAM_SERVER_HOST];
    NSInteger afterUSN = [ClientStateManager sharedmanager].lastUpdatedCount;
    if (afterUSN) {
        [stateUrl appendFormat:@"?after_usn=%d", afterUSN];
    }
    _managedObjectContext = [[CoreDataManager sharedManager] newManagedObjectContext];
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:stateUrl]];
    NSURLResponse *res;
    NSError *error;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&error];
    if (!jsonData) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];

    NSDate *fullSyncBefore = [state objectForKey:@"full_sync_before"] ? [NSDate dateWithTimeIntervalSince1970:[[state objectForKey:@"full_sync_before"] integerValue]] : nil ;
    NSInteger serverUpdateCount = [state objectForKey:@"update_count"] ? [[state objectForKey:@"update_count"] integerValue] : 0;
    
    NSDate *lastSyncTime = [ClientStateManager sharedmanager].lastSyncTime;
    NSInteger lastUpdatedCount = [ClientStateManager sharedmanager].lastUpdatedCount;
    self.progress = 0.2;
    NSLog(@"state %@", state);
    
    NSArray *syncronizedEntries = @[];
    NSArray *conflictedEntries = @[];
    if (self.isCancelled) return;

    // fullSyncbefore > lastSyncTime
    NSLog(@"before %@", fullSyncBefore);
    NSLog(@"last %@", lastSyncTime);
    
    if ([fullSyncBefore earlierDate:lastSyncTime] == lastSyncTime) {
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
        NSLog(@"Send changes");
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
        NSLog(@"Incremental Sync");
        // incremental sync
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
    NSMutableString *entriesUrl = [[NSString stringWithFormat:@"%@/server/api/entries", EDAM_SERVER_HOST] mutableCopy];
    if (afterUSN) {
        [entriesUrl appendFormat:@"?after_usn=%d", afterUSN];
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:entriesUrl]];
    NSURLResponse *res;
    NSError *requestError;
    NSError *jsonError;
    NSData *jsonData = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&requestError];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    NSArray *serverEntries = [json objectForKey:@"entries"];
    
    NSInteger serverUpdateCount = [[json objectForKey:@"server_update_count"] integerValue];
    NSDate *severCurrentTime = [NSDate dateWithTimeIntervalSince1970:[[json objectForKey:@"server_current_time"] integerValue]];

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(uuid IN %@ OR dirty == YES)", [serverEntries valueForKeyPath:@"uuid"]];
    NSError *fetchError;
    NSArray *clientEntries = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];

    NSDictionary *clientUUIDMap = [NSDictionary dictionaryWithObjects:clientEntries forKeys:[clientEntries valueForKeyPath:@"uuid"]];
    NSDictionary *serverUUIDMap = [NSDictionary dictionaryWithObjects:serverEntries forKeys:[serverEntries valueForKeyPath:@"uuid"]];
    
    NSSet *clientUUIDSet = [NSSet setWithArray:[clientEntries valueForKeyPath:@"uuid"]];
    NSSet *serverUUIDSet = [NSSet setWithArray:[serverEntries valueForKeyPath:@"uuid"]];
    
    NSMutableSet *willSaveUUIDSet = [serverUUIDSet mutableCopy];
    [willSaveUUIDSet minusSet:clientUUIDSet];
    
    NSMutableSet *clientOnlyUUIDSet = [clientUUIDSet mutableCopy];
    [clientOnlyUUIDSet minusSet:serverUUIDSet];
    
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
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:syncUrl]];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"content-type"];
    req.HTTPMethod = @"POST";
    NSMutableArray *convertedEntries = [@[] mutableCopy];
    for (NSManagedObject *entry in willSyncEntries) {
        [convertedEntries addObject:@{
            @"uuid"       : [entry valueForKey:@"uuid"],
            @"body"       : [entry valueForKey:@"body"],
            @"usn"        : [entry valueForKey:@"usn"],
            @"dirty"      : [entry valueForKey:@"dirty"],
            @"created_at" : [[entry valueForKey:@"created_at"] MySQLDateTime],
            @"updated_at" : [[entry valueForKey:@"updated_at"] MySQLDateTime],
         }];
    }
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{ @"entries": convertedEntries } options:0 error:&jsonError];
    NSMutableData * body = [[@"client=iphone&entries=" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [body appendData:jsonData];
    req.HTTPBody = body;
    NSURLResponse *res;
    NSError *requestError;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&requestError];
    if (!data) {
        NSLog(@"Unresolved error %@, %@", requestError, [requestError userInfo]);
        abort();
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    NSInteger severUpdateCount = [[json objectForKey:@"server_update_count"] ?: @(0) integerValue];
    NSDate *severCurrentTime = [NSDate dateWithTimeIntervalSince1970:[[json objectForKey:@"server_current_time"] integerValue]];
    NSArray *serverEntries = [json objectForKey:@"entries"];
    NSArray *conflictedEntries = [json objectForKey:@"conflicted_entries"] ?: @[];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
    NSArray *serverUUIDs = [serverEntries valueForKeyPath:@"uuid"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(uuid IN %@)", serverUUIDs.count ? serverUUIDs : @[]];
    NSError *fetchError;
    NSArray *clientEntries = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
    NSDictionary *clientUUIDMap = [NSDictionary dictionaryWithObjects:clientEntries forKeys:[clientEntries valueForKeyPath:@"uuid"]];
    
    NSMutableArray *syncronizedEntries = [@[] mutableCopy];
    for (NSDictionary *serverEntry in serverEntries) {
        NSManagedObject *clientEntry = [clientUUIDMap objectForKey:[serverEntry objectForKey:@"uuid"]];
        if ([[serverEntry objectForKey:@"usn"] integerValue] == lastUpdateCount + 1) {
            // last update count を更新する
        }
        else if ([[serverEntry objectForKey:@"usn"] integerValue] > lastUpdateCount + 1) {
            // incremental syncを実行する
        }
        [clientEntry setValue:[serverEntry valueForKey:@"body"] forKey:@"body"];
        [clientEntry setValue:[serverEntry valueForKey:@"usn"] forKey:@"usn"];
        [clientEntry setValue:@(NO) forKey:@"dirty"];
        [clientEntry setValue:[NSDate dateWithMySQLDateTime:[serverEntry valueForKey:@"updated_at"]] forKey:@"updated_at"];
        [syncronizedEntries addObject:clientEntry];
    }
    
    NSError *saveError;
    if (![_managedObjectContext save:&saveError]) {
        NSLog(@"Unresolved error %@, %@", saveError, [saveError userInfo]);
        abort();
    }
    
    [ClientStateManager sharedmanager].lastUpdatedCount = severUpdateCount;
    [ClientStateManager sharedmanager].lastSyncTime = severCurrentTime;

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
