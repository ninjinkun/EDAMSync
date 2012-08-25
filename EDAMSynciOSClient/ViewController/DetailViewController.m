//
//  DetailViewController.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/21/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "DetailViewController.h"

@interface DetailViewController ()
- (void)configureView;
@end

@implementation DetailViewController {
    IBOutlet UITextView *_bodyTextView;
    IBOutlet UILabel *_usnLabel;
    IBOutlet UILabel *_dirtyLabel;
    IBOutlet UILabel *_updatedAtLabel;
}

#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        
        // Update the view.
        [self configureView];
    }
}

- (void)configureView
{
    // Update the user interface for the detail item.

    if (self.detailItem) {
        _bodyTextView.text = [[self.detailItem valueForKey:@"body"] description];
        _dirtyLabel.text = [[self.detailItem valueForKey:@"dirty"] description];
        _usnLabel.text = [[self.detailItem valueForKey:@"usn"] description];
        _updatedAtLabel.text = [[self.detailItem valueForKey:@"updated_at"] description];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [self configureView];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.detailItem) {
        if (![_bodyTextView.text isEqualToString:[[self.detailItem valueForKey:@"body"] description]]) {
            [self.detailItem setValue:_bodyTextView.text forKey:@"body"];
            [self.detailItem setValue:@(YES) forKey:@"dirty"];
            [self.detailItem setValue:[NSDate date] forKey:@"updated_at"];
            NSError *error;
            [[self.detailItem managedObjectContext] save:&error];
        }
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

@end
