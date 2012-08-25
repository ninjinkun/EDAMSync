//
//  MasterViewController.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/21/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <CoreData/CoreData.h>

@interface MasterViewController : UITableViewController <NSFetchedResultsControllerDelegate, UIAlertViewDelegate>

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@end
