//
//  ResolveOperation.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/24/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "ResolveOperation.h"
#import "CoreDataManager.h"

@implementation ResolveOperation {
    NSManagedObjectContext *_managedObjectContext;
    NSArray *_conflictedEntries;
}

- (id)initWithConflictedEntries:(NSArray *)conflictedEntries
{
    self = [super init];
    if (self) {
        _conflictedEntries = conflictedEntries;
    }
    return self;
}

-(void)main {
    _managedObjectContext = [[CoreDataManager sharedManager] newManagedObjectContext];
    
    
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = [NSEntityDescription entityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(uuid IN %@)", [_conflictedEntries valueForKeyPath:@"client.uuid"]  ?: @[]];
    NSError *fetchError;
    NSArray *conflictedClientEntries = [_managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
    
    if (!conflictedClientEntries) {
        if (_completion) _completion(nil, fetchError);
    }
    
    NSMutableArray *newEntries = [@[] mutableCopy];
    
    NSDictionary *conflictedClientUUIDMap = [NSDictionary dictionaryWithObjects:conflictedClientEntries forKeys:[conflictedClientEntries valueForKeyPath:@"uuid"]];

    for (NSDictionary *dict in _conflictedEntries) {
        NSDictionary *serverEntry = [dict objectForKey:@"server"];
        NSDictionary *clientEntry = [dict objectForKey:@"client"];
        NSManagedObject *conflictedClientEntry = [conflictedClientUUIDMap objectForKey:[clientEntry objectForKey:@"uuid"]];
        
        if (self.isCancelled) return;
        
        // Overwrite conflicted entry
        [conflictedClientEntry setValue:[serverEntry valueForKey:@"body"] forKey:@"body"];
        [conflictedClientEntry setValue:[serverEntry valueForKey:@"usn"] forKey:@"usn"];
        [conflictedClientEntry setValue:@(NO) forKey:@"dirty"];
        [conflictedClientEntry setValue:[NSDate date] forKey:@"updated_at"];

        // Create new entry
        NSManagedObject *newEntry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry" inManagedObjectContext:_managedObjectContext];
        CFUUIDRef uuidObj = CFUUIDCreate(nil);
        NSString *uuidString = (__bridge NSString*)CFUUIDCreateString(nil, uuidObj);
        CFRelease(uuidObj);
        
        [newEntry setValue:uuidString forKey:@"uuid"];
        [newEntry setValue:[clientEntry valueForKey:@"body"] forKey:@"body"];
        [newEntry setValue:@(YES) forKey:@"dirty"];
        [newEntry setValue:[NSDate date] forKey:@"created_at"];
        [newEntry setValue:[NSDate date] forKey:@"updated_at"];

        [newEntries addObject:newEntry];        
    }
    NSError *saveError;
    if (![_managedObjectContext save:&saveError]) {
        if (_completion) _completion(nil, saveError);
        NSLog(@"Unresolved error %@, %@", saveError, [saveError userInfo]);
        abort();
    }
    
    if (_completion) _completion([newEntries valueForKeyPath:@"uuid"], nil);
}


@end
