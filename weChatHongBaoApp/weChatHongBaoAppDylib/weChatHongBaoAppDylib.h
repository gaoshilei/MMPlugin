//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  weChatHongBaoAppDylib.h
//  weChatHongBaoAppDylib
//
//  Created by 高石磊 on 2020/1/14.
//  Copyright (c) 2020 wechat. All rights reserved.
//

#import <Foundation/Foundation.h>

#define INSERT_SUCCESS_WELCOME "               🎉!!！congratulations!!！🎉\n👍----------------insert dylib success----------------👍\n"

@interface CustomViewController

@property (nonatomic, copy) NSString* newProperty;

+ (void)classMethod;

- (NSString*)getMyName;

- (void)newMethod:(NSString*) output;

@end
