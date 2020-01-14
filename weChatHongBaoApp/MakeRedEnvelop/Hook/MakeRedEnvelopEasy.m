//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  MakeRedEnvelopEasy.m
//  MakeRedEnvelopEasy
//
//  Created by 马旭 on 2017/8/7.
//  Copyright (c) 2017年 yolande. All rights reserved.
//

#import "MakeRedEnvelopEasy.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>

#import "WeChatRedEnvelop.h"
#import "WeChatRedEnvelopParam.h"
#import "WBSettingViewController.h"
#import "WBReceiveRedEnvelopOperation.h"
#import "WBRedEnvelopTaskManager.h"
#import "WBRedEnvelopConfig.h"
#import "WBRedEnvelopParamQueue.h"

CHDeclareClass(MicroMessengerAppDelegate)

CHOptimizedMethod2(self, BOOL, MicroMessengerAppDelegate, application, UIApplication*, application, didFinishLaunchingWithOptions, NSDictionary*, launchOptions) {
    return CHSuper2(MicroMessengerAppDelegate, application, application, didFinishLaunchingWithOptions, launchOptions);
}

CHDeclareClass(WCRedEnvelopesLogicMgr)

CHOptimizedMethod2(self, void, WCRedEnvelopesLogicMgr, OnWCToHongbaoCommonResponse, HongBaoRes*, arg1, Request, HongBaoReq*, arg2) {
    CHSuper2(WCRedEnvelopesLogicMgr, OnWCToHongbaoCommonResponse, arg1, Request, arg2);
    
    // 非参数查询请求
    if (arg1.cgiCmdid != 3) { return; }
    
    NSString *(^parseRequestSign)() = ^NSString *() {
        NSString *requestString = [[NSString alloc] initWithData:arg2.reqText.buffer encoding:NSUTF8StringEncoding];
        NSDictionary *requestDictionary = [objc_getClass("WCBizUtil") dictionaryWithDecodedComponets:requestString separator:@"&"];
        NSString *nativeUrl = [[requestDictionary stringForKey:@"nativeUrl"] stringByRemovingPercentEncoding];
        NSDictionary *nativeUrlDict = [objc_getClass("WCBizUtil") dictionaryWithDecodedComponets:nativeUrl separator:@"&"];
        
        return [nativeUrlDict stringForKey:@"sign"];
    };
    
    NSDictionary *responseDict = [[[NSString alloc] initWithData:arg1.retText.buffer encoding:NSUTF8StringEncoding] JSONDictionary];
    
    WeChatRedEnvelopParam *mgrParams = [[WBRedEnvelopParamQueue sharedQueue] dequeue];
    
    BOOL (^shouldReceiveRedEnvelop)() = ^BOOL() {
        
        // 手动抢红包
        if (!mgrParams) { return NO; }
        
        // 自己已经抢过
        if ([responseDict[@"receiveStatus"] integerValue] == 2) { return NO; }
        
        // 红包被抢完
        if ([responseDict[@"hbStatus"] integerValue] == 4) { return NO; }
        
        // 没有这个字段会被判定为使用外挂
        if (!responseDict[@"timingIdentifier"]) { return NO; }
        
        if (mgrParams.isGroupSender) { // 自己发红包的时候没有 sign 字段
            return [WBRedEnvelopConfig sharedConfig].autoReceiveEnable;
        } else {
            return [parseRequestSign() isEqualToString:mgrParams.sign] && [WBRedEnvelopConfig sharedConfig].autoReceiveEnable;
        }
    };
    
    if (shouldReceiveRedEnvelop()) {
        mgrParams.timingIdentifier = responseDict[@"timingIdentifier"];
        
        unsigned int delaySeconds = [self calculateDelaySeconds];
        WBReceiveRedEnvelopOperation *operation = [[WBReceiveRedEnvelopOperation alloc] initWithRedEnvelopParam:mgrParams delay:delaySeconds];
        
        if ([WBRedEnvelopConfig sharedConfig].serialReceive) {
            [[WBRedEnvelopTaskManager sharedManager] addSerialTask:operation];
        } else {
            [[WBRedEnvelopTaskManager sharedManager] addNormalTask:operation];
        }
    }
}

CHDeclareMethod0(unsigned int, WCRedEnvelopesLogicMgr, calculateDelaySeconds) {
    NSInteger configDelaySeconds = [WBRedEnvelopConfig sharedConfig].delaySeconds;
    
    if ([WBRedEnvelopConfig sharedConfig].serialReceive) {
        unsigned int serialDelaySeconds;
        if ([WBRedEnvelopTaskManager sharedManager].serialQueueIsEmpty) {
            serialDelaySeconds = configDelaySeconds;
        } else {
            serialDelaySeconds = 15;
        }
        
        return serialDelaySeconds;
    } else {
        return (unsigned int)configDelaySeconds;
    }
}

CHDeclareClass(CMessageMgr)

CHOptimizedMethod2(self, void, CMessageMgr, AsyncOnAddMsg, NSString*, msg, MsgWrap, CMessageWrap*, wrap) {
    CHSuper2(CMessageMgr, AsyncOnAddMsg, msg, MsgWrap, wrap);
    switch(wrap.m_uiMessageType) {
        case 49: { // AppNode
            /** 是否为红包消息 */
            BOOL (^isRedEnvelopMessage)() = ^BOOL() {
                return [wrap.m_nsContent rangeOfString:@"wxpay://"].location != NSNotFound;
            };
            
            if (isRedEnvelopMessage()) { // 红包
                CContactMgr *contactManager = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
                CContact *selfContact = [contactManager getSelfContact];
                BOOL (^isSender)() = ^BOOL() {
                    return [wrap.m_nsFromUsr isEqualToString:selfContact.m_nsUsrName];
                };
                /** 是否别人在群聊中发消息 */
                BOOL (^isGroupReceiver)() = ^BOOL() {
                    return [wrap.m_nsFromUsr rangeOfString:@"@chatroom"].location != NSNotFound;
                };
                /** 是否自己在群聊中发消息 */
                BOOL (^isGroupSender)() = ^BOOL() {
                    return isSender() && [wrap.m_nsToUsr rangeOfString:@"chatroom"].location != NSNotFound;
                };
                /** 是否抢自己发的红包 */
                BOOL (^isReceiveSelfRedEnvelop)() = ^BOOL() {
                    return [WBRedEnvelopConfig sharedConfig].receiveSelfRedEnvelop;
                };
                /** 是否在黑名单中 */
                BOOL (^isGroupInBlackList)() = ^BOOL() {
                    return [[WBRedEnvelopConfig sharedConfig].blackList containsObject:wrap.m_nsFromUsr];
                };
                /** 是否自动抢红包 */
                BOOL (^shouldReceiveRedEnvelop)() = ^BOOL() {
                    if (![WBRedEnvelopConfig sharedConfig].autoReceiveEnable) { return NO; }
                    if (isGroupInBlackList()) { return NO; }

                    return isGroupReceiver() || (isGroupSender() && isReceiveSelfRedEnvelop());
                };

                NSDictionary *(^parseNativeUrl)(NSString *nativeUrl) = ^(NSString *nativeUrl) {
                    nativeUrl = [nativeUrl substringFromIndex:[@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?" length]];
                    return [objc_getClass("WCBizUtil") dictionaryWithDecodedComponets:nativeUrl separator:@"&"];
                };

                /** 获取服务端验证参数 */
                void (^queryRedEnvelopesReqeust)(NSDictionary *nativeUrlDict) = ^(NSDictionary *nativeUrlDict) {
                    NSMutableDictionary *params = [@{} mutableCopy];
                    params[@"agreeDuty"] = @"0";
                    params[@"channelId"] = [nativeUrlDict stringForKey:@"channelid"];
                    params[@"inWay"] = @"0";
                    params[@"msgType"] = [nativeUrlDict stringForKey:@"msgtype"];
                    params[@"nativeUrl"] = [[wrap m_oWCPayInfoItem] m_c2cNativeUrl];
                    params[@"sendId"] = [nativeUrlDict stringForKey:@"sendid"];

                    WCRedEnvelopesLogicMgr *logicMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:[objc_getClass("WCRedEnvelopesLogicMgr") class]];
                    [logicMgr ReceiverQueryRedEnvelopesRequest:params];
                };

                /** 储存参数 */
                void (^enqueueParam)(NSDictionary *nativeUrlDict) = ^(NSDictionary *nativeUrlDict) {
                    WeChatRedEnvelopParam *mgrParams = [[WeChatRedEnvelopParam alloc] init];
                    mgrParams.msgType = [nativeUrlDict stringForKey:@"msgtype"];
                    mgrParams.sendId = [nativeUrlDict stringForKey:@"sendid"];
                    mgrParams.channelId = [nativeUrlDict stringForKey:@"channelid"];
                    mgrParams.nickName = [selfContact getContactDisplayName];
                    mgrParams.headImg = [selfContact m_nsHeadImgUrl];
                    mgrParams.nativeUrl = [[wrap m_oWCPayInfoItem] m_c2cNativeUrl];
                    mgrParams.sessionUserName = isGroupSender() ? wrap.m_nsToUsr : wrap.m_nsFromUsr;
                    mgrParams.sign = [nativeUrlDict stringForKey:@"sign"];

                    mgrParams.isGroupSender = isGroupSender();

                    [[WBRedEnvelopParamQueue sharedQueue] enqueue:mgrParams];
                };

                if (shouldReceiveRedEnvelop()) {
                    NSString *nativeUrl = [[wrap m_oWCPayInfoItem] m_c2cNativeUrl];
                    NSDictionary *nativeUrlDict = parseNativeUrl(nativeUrl);

                    queryRedEnvelopesReqeust(nativeUrlDict);
                    enqueueParam(nativeUrlDict);
                }
            }
            break;
        }
        default:
            break;
    }
    
}

/// 防撤回
CHOptimizedMethod1(self, void, CMessageMgr, onRevokeMsg,CMessageWrap*, arg1) {
    if (![WBRedEnvelopConfig sharedConfig].revokeEnable) {
        CHSuper1(CMessageMgr, onRevokeMsg, arg1);
    } else {
        if ([arg1.m_nsContent rangeOfString:@"<session>"].location == NSNotFound) { return; }
        if ([arg1.m_nsContent rangeOfString:@"<replacemsg>"].location == NSNotFound) { return; }

        NSString *(^parseSession)() = ^NSString *() {
            NSUInteger startIndex = [arg1.m_nsContent rangeOfString:@"<session>"].location + @"<session>".length;
            NSUInteger endIndex = [arg1.m_nsContent rangeOfString:@"</session>"].location;
            NSRange range = NSMakeRange(startIndex, endIndex - startIndex);
            return [arg1.m_nsContent substringWithRange:range];
        };

        NSString *(^parseSenderName)() = ^NSString *() {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<!\\[CDATA\\[(.*?)撤回了一条消息\\]\\]>" options:NSRegularExpressionCaseInsensitive error:nil];

            NSRange range = NSMakeRange(0, arg1.m_nsContent.length);
            NSTextCheckingResult *result = [regex matchesInString:arg1.m_nsContent options:0 range:range].firstObject;
            if (result.numberOfRanges < 2) { return nil; }

            return [arg1.m_nsContent substringWithRange:[result rangeAtIndex:1]];
        };

        CMessageWrap *msgWrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:0x2710];
        BOOL isSender = [objc_getClass("CMessageWrap") isSenderFromMsgWrap:arg1];

        NSString *sendContent;
        if (isSender) {
            [msgWrap setM_nsFromUsr:arg1.m_nsToUsr];
            [msgWrap setM_nsToUsr:arg1.m_nsFromUsr];
            sendContent = @"你撤回一条消息";
        } else {
            [msgWrap setM_nsToUsr:arg1.m_nsToUsr];
            [msgWrap setM_nsFromUsr:arg1.m_nsFromUsr];

            NSString *name = parseSenderName();
            sendContent = [NSString stringWithFormat:@"%@ 撤回消息被阻止❌", name ? name : arg1.m_nsFromUsr];
        }
        [msgWrap setM_uiStatus:0x4];
        [msgWrap setM_nsContent:sendContent];
        [msgWrap setM_uiCreateTime:[arg1 m_uiCreateTime]];

        [self AddLocalMsg:parseSession() MsgWrap:msgWrap fixTime:0x1 NewMsgArriveNotify:0x0];
    }
}

CHDeclareClass(NewSettingViewController)

CHDeclareMethod0(void, NewSettingViewController, setting) {
    WBSettingViewController *settingViewController = [WBSettingViewController new];
    [self.navigationController PushViewController:settingViewController animated:YES];
}

CHDeclareMethod0(void, NewSettingViewController, reloadTableData) {
    
    CHSuper0(NewSettingViewController, reloadTableData);
    WCTableViewManager *tableViewMgr = [self valueForKeyPath:@"m_tableViewMgr"];
    WCTableViewSectionManager *sectionInfo = [objc_getClass("WCTableViewSectionManager") sectionInfoDefaut];
    
    WCTableViewCellManager *settingCell = [objc_getClass("WCTableViewCellManager") normalCellForSel:@selector(setting) target:self title:@"微信小助手"];
    [sectionInfo addCell:settingCell];
        
    [tableViewMgr insertSection:sectionInfo At:0];
    
    MMTableView *tableView = [tableViewMgr getTableView];
    [tableView reloadData];
}


CHConstructor {
    
    CHLoadLateClass(MicroMessengerAppDelegate);
    CHHook2(MicroMessengerAppDelegate, application, didFinishLaunchingWithOptions);
    
    CHLoadLateClass(WCRedEnvelopesLogicMgr);
    CHHook2(WCRedEnvelopesLogicMgr, OnWCToHongbaoCommonResponse, Request);
    CHHook0(WCRedEnvelopesLogicMgr, calculateDelaySeconds);
    
    CHLoadLateClass(CMessageMgr);
    CHClassHook1(CMessageMgr, onRevokeMsg);
    CHHook2(CMessageMgr, AsyncOnAddMsg, MsgWrap);
}
