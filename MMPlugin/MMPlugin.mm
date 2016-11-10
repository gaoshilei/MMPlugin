//
//  MMPlugin.mm
//  MMPlugin
//
//  Created by 高石磊 on 2016/11/8.
//  Copyright (c) 2016年 __MyCompanyName__. All rights reserved.
//

// CaptainHook by Ryan Petrich
// see https://github.com/rpetrich/CaptainHook/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CaptainHook/CaptainHook.h"

// Objective-C runtime hooking using CaptainHook:
//   1. declare class using CHDeclareClass()
//   2. load class using CHLoadClass() or CHLoadLateClass() in CHConstructor
//   3. hook method using CHOptimizedMethod()
//   4. register hook using CHHook() in CHConstructor
//   5. (optionally) call old method using CHSuper()

/******************************************微信转发功能**********************************************************/
/**
 *  转发小视频至（朋友圈+朋友+保存到相册）
 **/

@class WCContentItemViewTemplateNewSight;
static int MenuShowCount = 0;
CHDeclareClass(WCContentItemViewTemplateNewSight); // declare class
//定义新方法，拿到小视频的WCMediaItem
CHDeclareMethod0(id, WCContentItemViewTemplateNewSight, SLSightDataItem)
{
    id responder = self;
    id SightCell = [[objc_getClass("MMTableViewCell") performSelector:@selector(alloc)] performSelector:@selector(init)];
    id SightTableView = [[objc_getClass("SightTableView") performSelector:@selector(alloc)] performSelector:@selector(init)];
    while (![responder isKindOfClass:NSClassFromString(@"WCTimeLineViewController")])
    {
        if ([responder isKindOfClass:NSClassFromString(@"MMTableViewCell")]){
            SightCell = responder;
        }
        else if ([responder isKindOfClass:NSClassFromString(@"MMTableView")]){
            SightTableView = responder;
        }
        responder = [responder performSelector:@selector(nextResponder) withObject:nil];
    }
    id WCTimelineVC = responder;
    NSIndexPath *indexPath = [SightTableView performSelector:@selector(indexPathForCell:) withObject:SightCell];
    long long sectionindex = (long long)[indexPath performSelector:@selector(section) withObject:nil];
    long long itemIndex = ((long long(*)(id,SEL,long long))objc_msgSend)(WCTimelineVC, @selector(calcDataItemIndex:), sectionindex);//经测试long long的参数类型不可以用id，否则会崩溃
    //微信服务中心
    Method MMServerMethod = class_getClassMethod(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
    IMP MMServerImp = method_getImplementation(MMServerMethod);
    id MMServerCenter = MMServerImp(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
    id facade = ((id(*)(id,SEL,Class))objc_msgSend)(MMServerCenter, @selector(getService:), objc_getClass("WCFacade"));
    id dataItem = ((id(*)(id,SEL,long long))objc_msgSend)(facade, @selector(getTimelineDataItemOfIndex:), itemIndex);
    id contentItem = [dataItem valueForKey:@"contentObj"];
    id mediaItem = [[contentItem valueForKey:@"mediaList" ] performSelector:@selector(objectAtIndex:) withObject:0];
    return mediaItem;
}

//保存小视频到本地
CHDeclareMethod0(void, WCContentItemViewTemplateNewSight, SLSightSaveToDisk)
{
    id dataItem = [self performSelector:@selector(SLSightDataItem)];//小视频的MediaItem
    NSString *localPath = [dataItem performSelector:@selector(pathForSightData) withObject:nil];
    UISaveVideoAtPathToSavedPhotosAlbum(localPath, nil, nil, nil);
}

//复制小视频链接
CHDeclareMethod0(void, WCContentItemViewTemplateNewSight, SLSightCopyUrl)
{
    id dataItem = objc_msgSend(self, @selector(SLSightDataItem));//小视频的MediaItem
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = [[dataItem valueForKey:@"dataUrl"] valueForKey:@"url"];
}

//转发小视频到朋友圈
CHDeclareMethod0(void, WCContentItemViewTemplateNewSight, SLRetweetSight)
{
    id editSightVC = [[objc_getClass("SightMomentEditViewController") performSelector:@selector(alloc)] performSelector:@selector(init)];
    id dataItem = objc_msgSend(self, @selector(SLSightDataItem));//小视频的MediaItem
    NSString *localPath = [dataItem performSelector:@selector(pathForSightData)];
    UIImage *image = [[self valueForKey:@"_sightView"] performSelector:@selector(getImage)];
    [editSightVC setValue:localPath forKey:@"realMoviePath"];
    [editSightVC setValue:localPath forKey:@"moviePath"];
    [editSightVC setValue:image forKey:@"realThumbImage"];
    [editSightVC setValue:image forKey:@"thumbImage"];
    [[self performSelector:@selector(SLTimeLineController)] presentViewController:editSightVC animated:YES completion:^{
        
    }];
}

//转发小视频给朋友
CHDeclareMethod0(void, WCContentItemViewTemplateNewSight, SLSightSendToFriends)
{
    [self performSelector:@selector(sendSightToFriend)];
}


//获得当前TimeLine控制器
CHDeclareMethod0(id, WCContentItemViewTemplateNewSight, SLTimeLineController)
{
    id responder = self;
    while (![responder isKindOfClass:NSClassFromString(@"WCTimeLineViewController")])
    {
        responder = [responder performSelector:@selector(nextResponder) withObject:nil];
    }
    return responder;
}

CHOptimizedMethod0(self, void, WCContentItemViewTemplateNewSight, onLongTouch) // hook method (with no arguments and no return value)
{
    MenuShowCount++;
    if (MenuShowCount % 2 != 0) return;
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    if (menuController.isMenuVisible) return;//防止出现menu闪屏的情况
    [self performSelector:@selector(becomeFirstResponder) withObject:nil];
    id dataItem = [self performSelector:@selector(SLSightDataItem) withObject:nil];//小视频的MediaItem
    NSString *localPath = [dataItem performSelector:@selector(pathForSightData) withObject:nil];//小视频的本地路径
    BOOL isExist =[[NSFileManager defaultManager] fileExistsAtPath:localPath];
    UIMenuItem *retweetMenuItem = [[UIMenuItem alloc] initWithTitle:@"朋友圈" action:@selector(SLRetweetSight)];
    UIMenuItem *saveToDiskMenuItem = [[UIMenuItem alloc] initWithTitle:@"保存到相册" action:@selector(SLSightSaveToDisk)];
    UIMenuItem *sendToFriendsMenuItem = [[UIMenuItem alloc] initWithTitle:@"好友" action:@selector(SLSightSendToFriends)];
    UIMenuItem *copyURLMenuItem = [[UIMenuItem alloc] initWithTitle:@"复制链接" action:@selector(SLSightCopyUrl)];
    if(isExist){
        [menuController setMenuItems:@[retweetMenuItem,sendToFriendsMenuItem,saveToDiskMenuItem,copyURLMenuItem]];
    }else{
        [menuController setMenuItems:@[copyURLMenuItem]];
    }
    [menuController setTargetRect:CGRectMake(0, 0, 0, 0) inView:(UIView *)self];
    [menuController setMenuVisible:YES animated:YES];
}

@class SightMomentEditViewController;
CHDeclareClass(SightMomentEditViewController);//小视频转发返回要pop控制器
CHOptimizedMethod0(self, void, SightMomentEditViewController, popSelf)
{
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}

/******************************************微信修改运动步数**********************************************************/
#define SAVESETTINGS(key, value, fileName) { \
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES); \
NSString *docDir = [paths objectAtIndex:0]; \
if (!docDir){ return;} \
NSMutableDictionary *dict = [NSMutableDictionary dictionary]; \
NSString *path = [docDir stringByAppendingPathComponent:fileName]; \
[dict setObject:value forKey:key]; \
[dict writeToFile:path atomically:YES]; \
}

static int StepCount = 6666;
static NSString *WeRunStepKey = @"WeRunStepKey";
static NSString *WeRunSettingFile = @"WeRunSettingFile.txt";
static NSString *HBPluginTypeKey = @"HBPluginType";
static NSString *HBPluginSettingFile = @"HBPluginSettingFile.txt";

//这里只是修改微信运动的步数，步数的设置放在放在抢红包功能（普通消息处理）里面
CHDeclareClass(WCDeviceStepObject)
CHMethod0(unsigned int, WCDeviceStepObject, m7StepCount) {
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithContentsOfFile:[docDir stringByAppendingPathComponent:WeRunSettingFile]];
    if (!dic){ return StepCount;}
    int value = ((NSNumber *)dic[WeRunStepKey]).intValue;
    if (value < 0) {
        return CHSuper(0, WCDeviceStepObject, m7StepCount);
    }
    return value;
}

/******************************************微信自动抢红包**********************************************************/
static int const kCloseRedEnvPlugin = 0;//关闭红包插件
static int const kOpenRedEnvPlugin = 1;//打开红包插件
static int const kCloseRedEnvPluginForMyself = 2;//不抢自己的红包
static int const kCloseRedEnvPluginForMyselfFromChatroom = 3;//不抢群里自己发的红包
static int HBPluginType = 0;

CHDeclareClass(CMessageMgr);
CHMethod2(void, CMessageMgr, AsyncOnAddMsg, id, arg1, MsgWrap, id, arg2) {
    CHSuper2(CMessageMgr, AsyncOnAddMsg, arg1, MsgWrap, arg2);
    Ivar uiMessageTypeIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_uiMessageType");
    ptrdiff_t offset = ivar_getOffset(uiMessageTypeIvar);
    unsigned char *stuffBytes = (unsigned char *)(__bridge void *)arg2;
    NSUInteger m_uiMessageType = * ((NSUInteger *)(stuffBytes + offset));
    
    Ivar nsFromUsrIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_nsFromUsr");
    id m_nsFromUsr = object_getIvar(arg2, nsFromUsrIvar);
    
    Ivar nsContentIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_nsContent");
    id m_nsContent = object_getIvar(arg2, nsContentIvar);
    
    switch(m_uiMessageType) {
        case 1://普通消息，打开或者关闭插件功能
        {
            //微信的服务中心
            Method methodMMServiceCenter = class_getClassMethod(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            IMP impMMSC = method_getImplementation(methodMMServiceCenter);
            id MMServiceCenter = impMMSC(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            //通讯录管理器
            id contactManager = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("CContactMgr"));
            id selfContact = objc_msgSend(contactManager, @selector(getSelfContact));
            
            Ivar nsUsrNameIvar = class_getInstanceVariable([selfContact class], "m_nsUsrName");
            id m_nsUsrName = object_getIvar(selfContact, nsUsrNameIvar);
            BOOL isMesasgeFromMe = NO;
            if ([m_nsFromUsr isEqualToString:m_nsUsrName]) {
                //发给自己的消息
                isMesasgeFromMe = YES;
            }
            
            if (isMesasgeFromMe)
            {
                if ([m_nsContent rangeOfString:@"打开红包插件"].location != NSNotFound)
                {
                    HBPluginType = kOpenRedEnvPlugin;
                }
                else if ([m_nsContent rangeOfString:@"关闭红包插件"].location != NSNotFound)
                {
                    HBPluginType = kCloseRedEnvPlugin;
                }
                else if ([m_nsContent rangeOfString:@"关闭抢自己红包"].location != NSNotFound)
                {
                    HBPluginType = kCloseRedEnvPluginForMyself;
                }
                else if ([m_nsContent rangeOfString:@"关闭抢自己群红包"].location != NSNotFound)
                {
                    HBPluginType = kCloseRedEnvPluginForMyselfFromChatroom;
                }else if ([m_nsContent rangeOfString:@"修改微信步数#"].location != NSNotFound)
                {
                    NSArray *array = [m_nsContent componentsSeparatedByString:@"#"];
                    if (array.count == 2) {
                        StepCount = ((NSNumber *)array[1]).intValue;
                    }
                } else if([m_nsContent rangeOfString:@"恢复微信步数"].location != NSNotFound) {
                    StepCount = -1;
                }
                //保存修改微信步数设置
                SAVESETTINGS(WeRunStepKey, [NSNumber numberWithInt:StepCount], WeRunSettingFile)
                //保存抢红包设置
                SAVESETTINGS(HBPluginTypeKey, [NSNumber numberWithInt:HBPluginType], HBPluginSettingFile);
            }
        }
            break;
        case 49://红包消息
        {
            NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:[docDir stringByAppendingPathComponent:HBPluginSettingFile]];
            if (dict){
                HBPluginType = ((NSNumber *)dict[HBPluginTypeKey]).intValue;
            }
            //微信的服务中心
            Method methodMMServiceCenter = class_getClassMethod(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            IMP impMMSC = method_getImplementation(methodMMServiceCenter);
            id MMServiceCenter = impMMSC(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            //红包控制器
            id logicMgr = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("WCRedEnvelopesLogicMgr"));
            //通讯录管理器
            id contactManager = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("CContactMgr"));
            
            Method methodGetSelfContact = class_getInstanceMethod(objc_getClass("CContactMgr"), @selector(getSelfContact));
            IMP impGS = method_getImplementation(methodGetSelfContact);
            id selfContact = impGS(contactManager, @selector(getSelfContact));
            
            Ivar nsUsrNameIvar = class_getInstanceVariable([selfContact class], "m_nsUsrName");
            id m_nsUsrName = object_getIvar(selfContact, nsUsrNameIvar);
            BOOL isMesasgeFromMe = NO;
            BOOL isChatroom = NO;
            if ([m_nsFromUsr isEqualToString:m_nsUsrName]) {
                isMesasgeFromMe = YES;
            }
            if ([m_nsFromUsr rangeOfString:@"@chatroom"].location != NSNotFound)
            {
                isChatroom = YES;
            }
            if (isMesasgeFromMe && kCloseRedEnvPluginForMyself == HBPluginType && !isChatroom) {
                //不抢自己的红包
                break;
            }
            else if(isMesasgeFromMe && kCloseRedEnvPluginForMyselfFromChatroom == HBPluginType && isChatroom)
            {
                //不抢群里自己的红包
                break;
            }
            
            if ([m_nsContent rangeOfString:@"wxpay://"].location != NSNotFound)
            {
                NSString *nativeUrl = m_nsContent;
                NSRange rangeStart = [m_nsContent rangeOfString:@"wxpay://c2cbizmessagehandler/hongbao"];
                if (rangeStart.location != NSNotFound)
                {
                    NSUInteger locationStart = rangeStart.location;
                    nativeUrl = [nativeUrl substringFromIndex:locationStart];
                }
                
                NSRange rangeEnd = [nativeUrl rangeOfString:@"]]"];
                if (rangeEnd.location != NSNotFound)
                {
                    NSUInteger locationEnd = rangeEnd.location;
                    nativeUrl = [nativeUrl substringToIndex:locationEnd];
                }
                
                NSString *naUrl = [nativeUrl substringFromIndex:[@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?" length]];
                
                NSArray *parameterPairs =[naUrl componentsSeparatedByString:@"&"];
                
                NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:[parameterPairs count]];
                for (NSString *currentPair in parameterPairs) {
                    NSRange range = [currentPair rangeOfString:@"="];
                    if(range.location == NSNotFound)
                        continue;
                    NSString *key = [currentPair substringToIndex:range.location];
                    NSString *value =[currentPair substringFromIndex:range.location + 1];
                    [parameters setObject:value forKey:key];
                }
                
                //红包参数
                NSMutableDictionary *params = [@{} mutableCopy];
                
                [params setObject:parameters[@"msgtype"]?:@"null" forKey:@"msgType"];
                [params setObject:parameters[@"sendid"]?:@"null" forKey:@"sendId"];
                [params setObject:parameters[@"channelid"]?:@"null" forKey:@"channelId"];
                
                id getContactDisplayName = objc_msgSend(selfContact, @selector(getContactDisplayName));
                id m_nsHeadImgUrl = objc_msgSend(selfContact, @selector(m_nsHeadImgUrl));
                
                [params setObject:getContactDisplayName forKey:@"nickName"];
                [params setObject:m_nsHeadImgUrl forKey:@"headImg"];
                [params setObject:[NSString stringWithFormat:@"%@", nativeUrl]?:@"null" forKey:@"nativeUrl"];
                [params setObject:m_nsFromUsr?:@"null" forKey:@"sessionUserName"];
                
                if (kCloseRedEnvPlugin != HBPluginType) {
                    //自动抢红包
                    ((void (*)(id, SEL, NSMutableDictionary*))objc_msgSend)(logicMgr, @selector(OpenRedEnvelopesRequest:), params);
                }
                return;
            }
            
            break;
        }
        default:
            break;
    }
}

//所有被hook的类和函数放在这里的构造函数中
CHConstructor
{
    @autoreleasepool
    {
        // CHLoadClass(ClassToHook); // load class (that is "available now")
        // CHLoadLateClass(ClassToHook);  // load class (that will be "available later")
        CHLoadLateClass(WCContentItemViewTemplateNewSight);
        CHHook(0, WCContentItemViewTemplateNewSight, onLongTouch);// register hook
        
        CHLoadLateClass(SightMomentEditViewController);
        CHHook(0, SightMomentEditViewController, popSelf);
        
        CHLoadLateClass(WCDeviceStepObject);
        CHHook0(WCDeviceStepObject, m7StepCount);
        
        CHLoadLateClass(CMessageMgr);
        CHHook2(CMessageMgr, AsyncOnAddMsg, MsgWrap);
    }
}
