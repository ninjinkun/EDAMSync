//
//  CoreDataManager.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/22/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "CoreDataManager.h"

@implementation CoreDataManager
//
//  CoreDataManager.m
//  BlogFeedback
//
//  Created by Asano Satoshi on 5/2/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;

+(CoreDataManager *)sharedManager {
    static id manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[CoreDataManager allocWithZone:NULL] init];
    });
    return manager;
}

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] init];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[self modelURL]];
    return __managedObjectModel;
}


- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}

-(NSURL *)modelURL {
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"EDAMSyncClient" withExtension:@"momd"];
    return modelURL;
}
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"EDAMSyncClient.sqlite"];
    
    NSError *error = nil;
    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                             [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    NSLog(@"migrating");
    
    if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    return __persistentStoreCoordinator;
}


- (BOOL)isRequiredMigration
{
    NSURL* fileURL = [self modelURL];
    NSError* error = nil;
    
    NSDictionary* sourceMetaData =
    [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                               URL:fileURL
                                                             error:&error];
    if (sourceMetaData == nil) {
        return NO;
    } else if (error) {
        NSLog(@"Checking migration was failed (%@, %@)", error, [error userInfo]);
        abort();
    }
    
    
    BOOL isCompatible = [self.managedObjectModel isConfiguration:nil
                                     compatibleWithStoreMetadata:sourceMetaData];
    return !isCompatible;
}

-(NSManagedObjectContext *)newManagedObjectContext {
    NSManagedObjectContext *context;
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        context = [[NSManagedObjectContext alloc] init];
        [context setPersistentStoreCoordinator:coordinator];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(anotherContextDidSave:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:context];
    }
    return context;
}

- (void)anotherContextDidSave:(NSNotification *)notification
{
    NSLog(@"anotherContextDidSave");
    // Merge changes into the main context on the main thread
    [self.managedObjectContext performSelectorOnMainThread:@selector(mergeChangesFromContextDidSaveNotification:)
                                  withObject:notification
                               waitUntilDone:YES];
}

@end
