//
//  CoreDataManager.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/22/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CoreDataManager : NSObject
@property (nonatomic,retain, readonly) NSPersistentStoreCoordinator* persistentStoreCoordinator;
@property (nonatomic,retain, readonly) NSManagedObjectModel* managedObjectModel;
@property (nonatomic,retain, readonly) NSManagedObjectContext* managedObjectContext;
+(CoreDataManager *)sharedManager;
-(BOOL)isRequiredMigration;
-(void)saveContext;
-(NSManagedObjectContext *)newManagedObjectContext;

@end
