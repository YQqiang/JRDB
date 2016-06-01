//
//  JRSqlGenerator.m
//  JRDB
//
//  Created by JMacMini on 16/5/10.
//  Copyright © 2016年 Jrwong. All rights reserved.
//

#import "JRSqlGenerator.h"
#import "JRReflectUtil.h"
#import "NSObject+JRDB.h"
#import "JRQueryCondition.h"

@import FMDB;

@implementation JRSqlGenerator

// create table 'tableName' (ID text primary key, 'p1' 'type1')
+ (NSString *)createTableSql4Clazz:(Class<JRPersistent>)clazz {
    
    NSDictionary *dict   = [JRReflectUtil ivarAndEncode4Clazz:clazz];
    NSString *tableName  = [JRReflectUtil shortClazzName:clazz];
    NSMutableString *sql = [NSMutableString string];
    
    [sql appendFormat:@"create table if not exists %@ (_ID text primary key ", tableName];
    for (NSString *name in dict.allKeys) {
        // 如果是关键字'ID' 或 '_ID' 或是 jr_excludePropertyNames 则继续循环
        if ([self isIgnoreProperty:name inClazz:clazz]) {continue;}
        
        // 如果是数据库不支持字段，则忽略，继续循环
        NSString *type = [self typeWithEncodeName:dict[name]];
        if (!type) {continue;}
        
        [sql appendFormat:@", %@ %@", name, type];
    }
    [sql appendString:@");"];
    NSLog(@"sql: %@", sql);
    return sql;
}

// {alter 'tableName' add column xx}
+ (NSArray<NSString *> *)updateTableSql4Clazz:(Class<JRPersistent>)clazz inDB:(FMDatabase *)db {
    NSString *tableName = [JRReflectUtil shortClazzName:clazz];
    // 检测表是否存在, 不存在则直接返回创建表语句
    if (![db tableExists:tableName]) { return @[[self createTableSql4Clazz:clazz]]; }
    
    NSDictionary *dict   = [JRReflectUtil ivarAndEncode4Clazz:clazz];
    NSArray *excludes    = [clazz jr_excludePropertyNames];
    NSMutableArray *sqls = [NSMutableArray array];
    
    // alter 'tableName' add 'name' 'type';
    for (NSString *name in dict.allKeys) {
        
        if (![db columnExists:name inTableWithName:tableName] && ![excludes containsObject:name]) {
            // 忽略不支持类型
            NSString *type = [self typeWithEncodeName:dict[name]];
            if (!type) { continue; }
            
            [sqls addObject:[NSString stringWithFormat:@"alter table %@ add column %@ %@ ;", tableName, name, type]];
        }
    }
    NSLog(@"sqls: %@", sqls);
    return sqls;
}


+ (NSString *)dropTableSql4Clazz:(Class<JRPersistent>)clazz {
    NSString *sql = [NSString stringWithFormat:@"drop table if exists %@ ;",[JRReflectUtil shortClazzName:clazz]];
    NSLog(@"sql: %@", sql);
    return sql;
}

// insert into tablename (_ID) values (?)
+ (NSString *)sql4Insert:(id<JRPersistent>)obj args:(NSArray *__autoreleasing *)args toDB:(FMDatabase * _Nonnull)db {
    
    NSString *tableName = [JRReflectUtil shortClazzName:[obj class]];
    
    NSMutableArray *argsList = [NSMutableArray array];
    NSDictionary *dict       = [JRReflectUtil ivarAndEncode4Clazz:[obj class]];
    NSMutableString *sql     = [NSMutableString string];
    NSMutableString *sql2    = [NSMutableString string];
    
    [sql appendFormat:@" insert into %@ ('_ID' ", tableName];
    [sql2 appendFormat:@" values ( ? "];
    
    for (NSString *name in dict.allKeys) {
        // 如果是关键字'ID' 或 '_ID' 或是 jr_excludePropertyNames 则继续循环
        if ([self isIgnoreProperty:name inClazz:[obj class]]) { continue; }
        
        // 检测字段是否存在
        if (![db columnExists:name inTableWithName:tableName]) { continue; }
        
        // 检测是否支持字段
        if (![self typeWithEncodeName:dict[name]]) { continue;}
        
        // 拼接语句
        [sql appendFormat:@", %@ ", name];
        [sql2 appendFormat:@", ? "];

        // 空值转换
        id value = [(NSObject *)obj valueForKey:name];
        if (!value) { value = [NSNull null]; }
        
        // 添加参数
        [argsList addObject:value];
    }
    
    [sql appendString:@")"];
    [sql2 appendString:@");"];
    [sql appendString:sql2];
    *args = argsList;
    
    NSLog(@"sql: %@", sql);
    return sql;
}

+ (NSString *)sql4Delete:(id<JRPersistent>)obj {
    NSString *sql = [NSString stringWithFormat:@"delete from %@ where %@ = ? ;", [JRReflectUtil shortClazzName:[obj class]], [[obj class] jr_primaryKey]];
    NSLog(@"sql: %@", sql);
    return sql;
}

// update 'tableName' set name = 'abc' where xx = xx
+ (NSString *)sql4Update:(id<JRPersistent>)obj columns:(NSArray<NSString *> *)columns args:(NSArray *__autoreleasing *)args toDB:(FMDatabase * _Nonnull)db {
    
    NSString *tableName      = [JRReflectUtil shortClazzName:[obj class]];
    NSMutableArray *argsList = [NSMutableArray array];
    NSMutableString *sql     = [NSMutableString string];
    NSDictionary *dict       = [JRReflectUtil ivarAndEncode4Clazz:[obj class]];
    
    [sql appendFormat:@" update %@ set ", tableName];
    
    for (NSString *name in dict.allKeys) {
        
        if ([self isIgnoreProperty:name inClazz:[obj class]]) { continue; }
        
        // 是否在指定更新列中
        if (columns.count && ![columns containsObject:name]) { continue; }
        
        // 检测字段是否存在
        if (![db columnExists:name inTableWithName:tableName]) { continue; }
        
        // 检测是否支持字段
        if (![self typeWithEncodeName:dict[name]]) { continue; }
        
        [sql appendFormat:@" %@ = ?,", name];
        
        // 空值转换
        id value = [(NSObject *)obj valueForKey:name];
        if (!value) { value = [NSNull null]; }
        
        [argsList addObject:value];
    }
    
    if ([sql hasSuffix:@","]) {
        sql = [[sql substringToIndex:sql.length - 1] mutableCopy];
    }
    
    [sql appendFormat:@" where %@ = ? ;", [[obj class] jr_primaryKey]];
    *args = argsList;
    NSLog(@"sql: %@", sql);
    return sql;
}

+ (NSString *)sql4GetByPrimaryKeyWithClazz:(Class<JRPersistent>)clazz {
    NSString *sql = [NSString stringWithFormat:@"select * from %@ where %@ = ?;", [JRReflectUtil shortClazzName:clazz], [clazz jr_primaryKey]];
    NSLog(@"sql: %@", sql);
    return sql;
}

+ (NSString *)sql4FindAll:(Class<JRPersistent>)clazz orderby:(NSString *)orderby isDesc:(BOOL)isDesc {
    NSString *sql = [NSString stringWithFormat:@"select * from %@ ", [JRReflectUtil shortClazzName:clazz]];
    if (orderby.length) {
        sql = [sql stringByAppendingFormat:@" order by %@ ", orderby.length ? orderby : [clazz jr_primaryKey]];
    }
    sql = [sql stringByAppendingFormat:@" %@ ;", isDesc ? @"desc" : @""];
    NSLog(@"sql: %@", sql);
    return sql;
}

+ (NSString *)sql4FindByConditions:(NSArray<JRQueryCondition *> *)conditions clazz:(Class<JRPersistent>)clazz groupBy:(NSString *)groupBy orderBy:(NSString *)orderBy limit:(NSString *)limit isDesc:(BOOL)isDesc args:(NSArray *__autoreleasing *)args {
    
    NSMutableArray *argList = [NSMutableArray array];
    NSMutableString *sql    = [NSMutableString string];
    
    [sql appendFormat:@" select * from %@ where 1=1 ", [JRReflectUtil shortClazzName:clazz]];
    
    for (JRQueryCondition *condition in conditions) {
        
        [sql appendFormat:@" %@ (%@)", condition.type == JRQueryConditionTypeAnd ? @"and" : @"or", condition.condition];
        
        if (condition.args.count) {
            [argList addObjectsFromArray:condition.args];
        }
    }
    
    // group
    if (groupBy.length) { [sql appendFormat:@" group by %@ ", groupBy]; }
    // orderby
    [sql appendFormat:@" order by %@ ", orderBy.length ? orderBy : [clazz jr_primaryKey]];
    // desc asc
    if (isDesc) {[sql appendString:@" desc "];}
    // limit
    if (limit.length) { [sql appendFormat:@" %@ ", limit]; }
    
    [sql appendString:@";"];
    *args = argList;
    NSLog(@"sql: %@", sql);
    return sql;
}

+ (NSString *)typeWithEncodeName:(NSString *)encode {
    if ([encode isEqualToString:[NSString stringWithUTF8String:@encode(int)]]
        ||[encode isEqualToString:[NSString stringWithUTF8String:@encode(unsigned int)]]
        ||[encode isEqualToString:[NSString stringWithUTF8String:@encode(long)]]
        ||[encode isEqualToString:[NSString stringWithUTF8String:@encode(unsigned long)]]
        ) {
        return @"INTEGER";
    }
    if ([encode isEqualToString:[NSString stringWithUTF8String:@encode(float)]]
        ||[encode isEqualToString:[NSString stringWithUTF8String:@encode(double)]]
        ) {
        return @"REAL";
    }
    if ([encode rangeOfString:@"String"].length) {
        return @"TEXT";
    }
    if ([encode rangeOfString:@"NSNumber"].length) {
        return @"REAL";
    }
    if ([encode rangeOfString:@"NSData"].length) {
        return @"BLOB";
    }
    if ([encode rangeOfString:@"NSDate"].length) {
        return @"TIMESTAMP";
    }
    return nil;
}

#pragma mark - private method
+ (BOOL)isIgnoreProperty:(NSString *)property inClazz:(Class<JRPersistent>)clazz {
    NSArray *excludes = [clazz jr_excludePropertyNames];
    return [excludes containsObject:property] || isID(property);
}

@end
