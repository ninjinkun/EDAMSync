//
//  NSDate+MySQL.m
//  EDAMSyncClient
//
//  Created by 浅野 慧 on 8/23/12.
//  Copyright (c) 2012 Satoshi Asano. All rights reserved.
//

#import "NSDate+MySQL.h"

@implementation NSDate(MySQL)
+(NSDate *)dateWithMySQLDateTime:(NSString *)mysqlDateTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [formatter dateFromString:mysqlDateTime];
}

-(NSString *)MySQLDateTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [formatter stringFromDate:self];
}

@end
