//
//  NSDate+MySQL.h
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/23/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (MySQL)
+(NSDate *)dateWithMySQLDateTime:(NSString *)mysqlDateTime;
-(NSString *)MySQLDateTime;
@end
