本人博客地址：[传送门](http://www.gaoshilei.com)
#	前言
此文为逆向微信二进制文件，实现朋友圈小视频转发的教程，从最开始的汇编代码入手到最后重签名安装等操作，手把手教你玩转微信！学会之后再去逆向微信其他功能易如反掌。  
本篇文章由于篇幅太长分成了两篇，**上篇**讲解的是逆向工作，也就是怎么找到相关的函数和方法实现，**下篇**讲解的是怎么在非越狱机重签名安装和越狱机tweak安装的详细过程。  
**正文的第二部分还提供了微信自动抢红包、修改微信步数的代码，这些都可以照葫芦画瓢按照本文的套路一步步逆向找到，这里就不再赘述。**  
在实践之前，需要准备好一部越狱的手机，然后将下文列出的所有工具安装好。IDA跟Reveal都是破解版，IDA的正版要2000多刀，对于这么牛逼的逆向工具确实物有所值，不过不是专门研究逆向的公司也没必要用正版的，下个Windows的破解版就好，Mac上暂时没找到。Mac上可以用hopper代替IDA，也是一款很牛逼的逆向工具。废话不多说，正式开始吧！
  

#	正文
## 一、获取朋友圈的小视频
>	注意：本文逆向的微信的二进制文件为6.3.28版本，如果是不同的微信版本，二进制文件中的基地址也不相同

####	本文涉及到的工具  
1. [cycript](http://www.cycript.org) 
2. LLDB与debugserver（Xcode自带）
3. OpenSSH
4. IDA
5. Reveal
6. [theos](https://github.com/theos/theos)
7. [CydiaSubstrate](http://www.cydiasubstrate.com)
8. iOSOpenDev
9. ideviceinstaller
10. tcprelay（本地端口映射，USB连接SSH，不映射可通过WiFi连接） 
11. [dumpdecrypted](https://github.com/stefanesser/dumpdecrypted)
12. [class-dump](http://stevenygard.com/projects/class-dump/) 
13. [iOS App Signer](https://github.com/DanTheMan827/ios-app-signer)
14. 编译好的[yololib](https://github.com/gaoshilei/yololib)

**逆向环境为MacOS	+	iPhone5S 9.1越狱机**  
先用dumpdecrypted给微信砸壳（不会的请我写的看[这篇教程](http://www.gaoshilei.com/2016/08/08/dumpdecrypted给App砸壳/)），获得一个WeChat.decrypted文件，先把这个文件扔到IDA中分析（60MB左右的二进制文件，IDA差不多40分钟才能分析完），用class-dump导出所有头文件  

```
LeonLei-MBP:~ gaoshilei$ class-dump -S -s -H /Users/gaoshilei/Desktop/reverse/binary_for_class-dump/WeChat.decrypted -o /Users/gaoshilei/Desktop/reverse/binary_for_class-dump/class-Header/WeChat
``` 
我滴个亲娘！一共有8000个头文件，微信果然工程量浩大！稳定一下情绪，理一理思路继续搞。要取得小视频的下载链接，找到播放视频的View，顺藤摸瓜就能找到小视频的URL。用Reveal查看小视频的播放窗口
![Reveal](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E5%B0%8F%E8%A7%86%E9%A2%91%E8%BD%AC%E5%8F%91Reveal.png)  
可以看出来WCContentItemViewTemplateNewSigh这个对象是小视频的播放窗口，它的subView有WCSightView，SightView、SightPlayerView，这几个类就是我们的切入点。
保存视频到favorite的时候是长按视频弹出选项的，那么在WCContentItemViewTemplateNewSight这个类里面可能有手势相关的方法，去刚才导出的头文件中找线索。  

```
- (void)onLongTouch;
- (void)onLongPressedWCSight:(id)arg1;
- (void)onLongPressedWCSightFullScreenWindow:(id)arg1;
```
这几个方法跟长按手势相关，再去IDA中找到这些函数，逐个查看。onLongPressedWCSight和onLongPressedWCSightFullScreenWindow都比较简单，onLongTouch比较长，而且发现了内部调用了方法Favorites_Add，因为长按视频的时候出来一个选项就是Favorites，并且我看到这个函数调用  

```
ADRP            X8, #selRef_sightVideoPath@PAGE
LDR             X1, [X8,#selRef_sightVideoPath@PAGEOFF]
```
这里拿到了小视频的地址，可以推测这个函数跟收藏有关，下面打断点测试。  

```
(lldb) im li -o -f
[  0] 0x000000000003c000 /var/mobile/Containers/Bundle/Application/2F1D52EC-C57E-4F95-B715-EF04351232E8/WeChat.app/WeChat(0x000000010003c000)
```
可以看到WeChat的ASLR为0x3c000，在IDA查找到这三个函数的基地址，分别下断点  

```
(lldb) br s -a 0x1020D3A10+0x3c000
Breakpoint 1: where = WeChat`___lldb_unnamed_symbol110094$$WeChat + 28, address = 0x000000010210fa10
(lldb) br s -a 0x1020D3370+0x3c000
Breakpoint 2: where = WeChat`___lldb_unnamed_symbol110091$$WeChat + 8, address = 0x000000010210f370
(lldb) br s -a 0x1020D33E4+0x3c000
Breakpoint 3: where = WeChat`___lldb_unnamed_symbol110092$$WeChat + 12, address = 0x000000010210f3e4
```
回到微信里面长按小视频，看断点触发情况  

```
Process 3721 stopped
* thread #1: tid = 0x658fc, 0x000000010210f370 WeChat`___lldb_unnamed_symbol110091$$WeChat + 8, queue = 'com.apple.main-thread', stop reason = breakpoint 2.1
    frame #0: 0x000000010210f370 WeChat`___lldb_unnamed_symbol110091$$WeChat + 8
WeChat`___lldb_unnamed_symbol110091$$WeChat:
->  0x10210f370 <+8>:  add    x29, sp, #16              ; =16 
    0x10210f374 <+12>: mov    x19, x0
    0x10210f378 <+16>: adrp   x8, 4968
    0x10210f37c <+20>: ldr    x0, [x8, #744]
(lldb) c
Process 3721 resuming
Process 3721 stopped
* thread #1: tid = 0x658fc, 0x000000010210fa10 WeChat`___lldb_unnamed_symbol110094$$WeChat + 28, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
    frame #0: 0x000000010210fa10 WeChat`___lldb_unnamed_symbol110094$$WeChat + 28
WeChat`___lldb_unnamed_symbol110094$$WeChat:
->  0x10210fa10 <+28>: add    x29, sp, #96              ; =96 
    0x10210fa14 <+32>: sub    sp, sp, #96               ; =96 
    0x10210fa18 <+36>: mov    x19, x0
    0x10210fa1c <+40>: adrp   x8, 4863
……
```
发现断点2先被触发，接着触发断点1，后面断点2和1又各触发了1次，断点3一直很安静。可以排除onLongPressedWCSightFullScreenWindow与收藏小视频的联系。小视频的踪影就要在剩下的两个方法中寻找了。通过V找到C，顺藤摸瓜找到M屡试不爽！用cycript注入WeChat，拿到播放小视频的view所在的Controller。  

```
cy# [#0x138c18030 nextResponder]
#"<WCTimeLineCellView: 0x138c34620; frame = (0 0; 319 249); tag = 1048577; layer = <CALayer: 0x138362ba0>>"
cy# [#0x138c34620 nextResponder]
#"<UITableViewCellContentView: 0x138223c70; frame = (0 0; 320 256); gestureRecognizers = <NSArray: 0x1384ec480>; layer = <CALayer: 0x138081dc0>>"
cy# [#0x138223c70 nextResponder]
#"<MMTableViewCell: 0x138c9f930; baseClass = UITableViewCell; frame = (0 307; 320 256); autoresize = W; layer = <CALayer: 0x1382dcd10>>"
cy# [#0x138c9f930 nextResponder]
#"<UITableViewWrapperView: 0x137b57800; frame = (0 0; 320 504); gestureRecognizers = <NSArray: 0x1383db660>; layer = <CALayer: 0x138af20c0>; contentOffset: {0, 0}; contentSize: {320, 504}>"
cy# [#0x137b57800 nextResponder]
#"<MMTableView: 0x137b8ae00; baseClass = UITableView; frame = (0 0; 320 568); gestureRecognizers = <NSArray: 0x138adb590>; layer = <CALayer: 0x138956890>; contentOffset: {0, 99.5}; contentSize: {320, 3193}>"
cy# [#0x137b8ae00 nextResponder]
#"<UIView: 0x138ade5c0; frame = (0 0; 320 568); autoresize = W+H; layer = <CALayer: 0x138ac9990>>"
cy# [#0x138ade5c0 nextResponder]
#"<WCTimeLineViewController: 0x1379eb000>"
```
通过响应者链条找到
WCContentItemViewTemplateNewSight所属的Controller为WCTimeLineViewController。在这个类的头文件中并没有发现有价值的线索，不过我们注意到小视频所在的view是属于MMTableVIewCell的（见上图Reveal分析图），这是每一个iOS最熟悉的TableView，cell的数据是通过UITableViewDataSource的代理方法`- tableView:cellForRowAtIndexPath:`赋值的，通过这个方法肯定能知道到M的影子。在IDA中找到`[WCTimeLineViewController tableView:cellForRowAtIndexPath:]`,定位到基地址0x10128B6B0位置：

```
__text:000000010128B6B0     ADRP     X8, #selRef_genNormalCell_indexPath_@PAGE
```
这里的函数是WCTimeLineViewController中生成cell的方法，除了这个方法在这个类中还有另外三个生成cell的方法：

```
- (void)genABTestTipCell:(id)arg1 indexPath:(id)arg2;
- (void)genRedHeartCell:(id)arg1 indexPath:(id)arg2;
- (void)genUploadFailCell:(id)arg1 indexPath:(id)arg2;
``` 
通过字面意思可以猜测出normal这个应该是生成小视频cell的方法。继续在IDA中寻找线索

```
__text:0000000101287CC8     ADRP     X8, #selRef_getTimelineDataItemOfIndex_@PAGE
```
在`genNormalCell:IndexPath:`方法中发现上面这个方法，可以大胆猜想这个方法是获取TimeLine（朋友圈）数据的方法，那小视频的数据肯定也是通过这个方法获取的，并且IDA可以看到这个方法中调用一个叫做`selRef_getTimelineDataItemOfIndex_`的方法，获取DataItem貌似就是cell的数据源啊！接下来用LLDB下断点验证猜想。
通过IDA可以找到这个方法对应的基地址为：0x101287CE4，先打印正在运行WeChat的ASLR偏移

```
LeonLei-MBP:~ gaoshilei$ lldb
(lldb) process connect connect://localhost:1234
(lldb) im li -o -f 
[0] 0x0000000000050000 /var/mobile/Containers/Bundle/Application/2DCE8F30-9B6B-4652-901C-37EB1FF2A40D/WeChat.app/WeChat(0x0000000100050000)
```
所以我们下断点的位置是0x50000+0x101287CE4  

```
(lldb) br s -a 0x50000+0x101287CE4
Breakpoint 1: where = WeChat`___lldb_unnamed_symbol63721$$WeChat + 252, address = 0x00000001012d7ce4
```
打印x0的值

```
(lldb) po $x0
Class name: WCDataItem, addr: 0x15f5f03b0
tid: 12393001887435993280
username: wxid_z8twcz4o18fg12
createtime: 1477360950
commentUsers: (
)
contentObj: <WCContentItem: 0x15f57d000>

```
得到一个WCDataItem的对象，这里x0的值就是`selRef_getTimelineDataItemOfIndex_`执行完的返回值，然后把x0的值改掉

```
(lldb) register write $x0 0
(lldb) c
```
此时会发现我们要刷新的那条小视频内容全部为空  
![小视频内容为空](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E5%B0%8F%E8%A7%86%E9%A2%91-%E8%BD%AC%E5%8F%91%E5%B0%8F%E8%A7%86%E9%A2%91%E4%B8%BA%E7%A9%BA.jpg)  
到这里已经找到了小视频的源数据获取方法，问题是我们怎么拿到这个WCDataItem呢？继续看IDA分析函数的调用情况：
>	WCTimeLineViewController - (void)genNormalCell:(id) indexPath:(id)
 
```
__text:0000000101287BCC                 STP             X28, X27, [SP,#var_60]!
__text:0000000101287BD0                 STP             X26, X25, [SP,#0x60+var_50]
__text:0000000101287BD4                 STP             X24, X23, [SP,#0x60+var_40]
__text:0000000101287BD8                 STP             X22, X21, [SP,#0x60+var_30]
__text:0000000101287BDC                 STP             X20, X19, [SP,#0x60+var_20]
__text:0000000101287BE0                 STP             X29, X30, [SP,#0x60+var_10]
__text:0000000101287BE4                 ADD             X29, SP, #0x60+var_10
__text:0000000101287BE8                 SUB             SP, SP, #0x80
__text:0000000101287BEC                 MOV             X19, X3
__text:0000000101287BF0                 MOV             X22, X0
__text:0000000101287BF4                 MOV             W25, #0x100000
__text:0000000101287BF8                 MOVK            W25, #1
__text:0000000101287BFC                 MOV             X0, X2
__text:0000000101287C00                 BL              _objc_retain
__text:0000000101287C04                 MOV             X28, X0
__text:0000000101287C08                 MOV             X0, X19
__text:0000000101287C0C                 BL              _objc_retain
__text:0000000101287C10                 MOV             X20, X0
__text:0000000101287C14                 STR             X20, [SP,#0xE0+var_98]
__text:0000000101287C18                 ADRP            X8, #selRef_row@PAGE
__text:0000000101287C1C                 LDR             X1, [X8,#selRef_row@PAGEOFF]
__text:0000000101287C20                 BL              _objc_msgSend
__text:0000000101287C24                 MOV             X26, X0
__text:0000000101287C28                 ADRP            X8, #selRef_section@PAGE
__text:0000000101287C2C                 LDR             X19, [X8,#selRef_section@PAGEOFF]
__text:0000000101287C30                 MOV             X0, X20
__text:0000000101287C34                 MOV             X1, X19
__text:0000000101287C38                 BL              _objc_msgSend
__text:0000000101287C3C                 STR             X0, [SP,#0xE0+var_A8]
__text:0000000101287C40                 MOV             X0, X20
__text:0000000101287C44                 MOV             X1, X19
__text:0000000101287C48                 BL              _objc_msgSend
__text:0000000101287C4C                 MOV             X2, X0
__text:0000000101287C50                 ADRP            X8, #selRef_calcDataItemIndex_@PAGE
__text:0000000101287C54                 LDR             X1, [X8,#selRef_calcDataItemIndex_@PAGEOFF]
__text:0000000101287C58                 MOV             X0, X22
__text:0000000101287C5C                 BL              _objc_msgSend
__text:0000000101287C60                 MOV             X21, X0
__text:0000000101287C64                 STR             X21, [SP,#0xE0+var_C0]
__text:0000000101287C68                 ADRP            X8, #classRef_MMServiceCenter@PAGE
__text:0000000101287C6C                 LDR             X0, [X8,#classRef_MMServiceCenter@PAGEOFF]
__text:0000000101287C70                 ADRP            X8, #selRef_defaultCenter@PAGE
__text:0000000101287C74                 LDR             X1, [X8,#selRef_defaultCenter@PAGEOFF]
__text:0000000101287C78                 STR             X1, [SP,#0xE0+var_B8]
__text:0000000101287C7C                 BL              _objc_msgSend
__text:0000000101287C80                 MOV             X29, X29
__text:0000000101287C84                 BL              _objc_retainAutoreleasedReturnValue
__text:0000000101287C88                 MOV             X19, X0
__text:0000000101287C8C                 ADRP            X8, #classRef_WCFacade@PAGE
__text:0000000101287C90                 LDR             X0, [X8,#classRef_WCFacade@PAGEOFF]
__text:0000000101287C94                 ADRP            X8, #selRef_class@PAGE
__text:0000000101287C98                 LDR             X1, [X8,#selRef_class@PAGEOFF]
__text:0000000101287C9C                 STR             X1, [SP,#0xE0+var_B0]
__text:0000000101287CA0                 BL              _objc_msgSend
__text:0000000101287CA4                 MOV             X2, X0
__text:0000000101287CA8                 ADRP            X8, #selRef_getService_@PAGE
__text:0000000101287CAC                 LDR             X1, [X8,#selRef_getService_@PAGEOFF]
__text:0000000101287CB0                 STR             X1, [SP,#0xE0+var_A0]
__text:0000000101287CB4                 MOV             X0, X19
__text:0000000101287CB8                 BL              _objc_msgSend
__text:0000000101287CBC                 MOV             X29, X29
__text:0000000101287CC0                 BL              _objc_retainAutoreleasedReturnValue
__text:0000000101287CC4                 MOV             X20, X0
__text:0000000101287CC8                 ADRP            X8, #selRef_getTimelineDataItemOfIndex_@PAGE
__text:0000000101287CCC                 LDR             X1, [X8,#selRef_getTimelineDataItemOfIndex_@PAGEOFF]
__text:0000000101287CD0                 STR             X1, [SP,#0xE0+var_C8]
__text:0000000101287CD4                 MOV             X2, X21
__text:0000000101287CD8                 BL              _objc_msgSend
__text:0000000101287CDC                 MOV             X29, X29
__text:0000000101287CE0                 BL              _objc_retainAutoreleasedReturnValue
__text:0000000101287CE4                 MOV             X21, X0
__text:0000000101287CE8                 MOV             X0, X20
......
```  
`selRef_getTimelineDataItemOfIndex_ `传入的参数是x2，可以看到传值给x2的x21是函数`selRef_calcDataItemIndex_ `的返回值，是一个unsigned long数据类型。继续分析，`selRef_getTimelineDataItemOfIndex_ `函数的调用者是上一步`selRef_getService_ `的返回值，经过断点分析发现是一个`WCFacade`对象。整理一下`selRef_getTimelineDataItemOfIndex_ `的调用：  
**调用者是`selRef_getService_ `的返回值；参数是`selRef_calcDataItemIndex_ `的返回值**  
下面把目光转向那两个函数，用相同的原理分析它们各自怎么实现调用  
1.	先看`selRef_getService_`：  
在0x101287CB4这个位置可以发现，这个函数的调用者是从通过x19 MOV的，打印x19发现是一个`MMServiceCenter`对象，往上找x19是在0x101287C88这个位置赋值的，结果很清晰x19是`[MMServiceCenter defaultCenter]`的返回值。   
在0x101287CA4位置可以找到传入的参数x2，往上分析可以看出来它的参数是`[WCFacade class]`的返回值。  
2.	接着找`selRef_calcDataItemIndex_ `：  
在0x101287C58的位置找到它的调用者x0，x0通过x22赋值，继续向上寻找，发现在最上面0x101287BF0的位置，x22是x0赋值的，一开始的x0就是`WCTimeLineViewController`自身。  
在0x101287C4C位置发现传入的参数来自x2,x2是通过上一步`selRef_section`函数的返回值x0赋值的，在0x101287C30位置可以发现`selRef_section`函数的调用者是x20赋值的，如下图所示，最终找到`selRef_section`的调用者是x3  
![selRef_section函数的调用者](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E5%B0%8F%E8%A7%86%E9%A2%91%E8%BD%AC%E5%8F%91-selRef_section%E5%87%BD%E6%95%B0%E7%9A%84%E8%B0%83%E7%94%A8%E8%80%85.png)  
x3就是函数` WCTimeLineViewController - (void)genNormalCell:(id) indexPath:(id)`的第二个参数indexPath,，所以`selRef_calcDataItemIndex_ `的参数是`[IndexPath section]`。  
对上面的分析结果做个梳理：  
因此`getTimelineDataItemOfIndex:`的调用者可以通过

```OC
[[MMServiceCenter defaultCenter] getService:[WCFacade class]]
```
来获得,它的参数可以通过下面的函数获取

```OC
[WCTimeLineViewController calcDataItemIndex:[indexPath section]]
```
总感觉还少点什么？indexPath我们还没拿到呢！下一步就是拿到indexPath,这个就比较简单了，因为我们位于`[WCContentItemViewTemplateNewSight onLongTouch]`中，所以可以通过`[self nextResponder]`依次拿到MMTableViewCell、MMTableView和WCTimeLineViewController，再通过`[MMTableView indexPathForCell:MMTableViewCell]`拿到indexPath。  
做完这些，已经拿到WCDataItem对象，接下来的重点要放在WCDataItem上，最终要获取我们要的小视频。到这个类的头文件中找线索，因为视频是下载完成后才能播放的，所以这里应该拿到了视频的路径，所以要注意url和path相关的属性或方法，然后找到下面这几个嫌疑对象  

```OC
@property(retain, nonatomic) NSString *sourceUrl2; 
@property(retain, nonatomic) NSString *sourceUrl; 
- (id)descriptionForKeyPaths;
- (id)keyPaths;
```  
回到LLDB中，用断点打印这些值，看看有什么。  

```OC
(lldb) po [$x0 keyPaths]
<__NSArrayI 0x15f74e9d0>(
	tid,
	username,
	createtime,
	commentUsers,
	contentObj
)
(lldb) po [$x0 descriptionForKeyPaths]
Class name: WCDataItem, addr: 0x15f5f03b0
tid: 12393001887435993280
username: wxid_z8twcz4o18fg12
createtime: 1477360950
commentUsers: (
)
contentObj: <WCContentItem: 0x15f57d000>
(lldb) po [$x0 sourceUrl]
 nil
(lldb) po [$x0 sourceUrl2]
 nil
```
并没有什么有价值的线索，不过注意到WCDataItem里面有一个WCContentItem，看来只能从这儿入手了，去看一下头文件吧！  

```OC
@property(retain, nonatomic) NSString *linkUrl; 
@property(retain, nonatomic) NSString *linkUrl2; 
@property(retain, nonatomic) NSMutableArray *mediaList;
```
在LLDB打印出来  

```OC
(lldb) po [[$x0 valueForKey:@"contentObj"] linkUrl]
https://support.weixin.qq.com/cgi-bin/mmsupport-bin/readtemplate?t=page/common_page__upgrade&v=1
(lldb) po [[$x0 valueForKey:@"contentObj"] linkUrl2]
 nil
(lldb) po [[$x0 valueForKey:@"contentObj"] mediaList]
<__NSArrayM 0x15f985e10>(
<WCMediaItem: 0x15dfebdf0>
)
```
mediaList数组里面有一个WCMediaItem对象，Media一般用来表示视频和音频，大胆猜测就是它了！赶紧找到头文件搜索一遍。  

```OC
@property(retain, nonatomic) WCUrl *dataUrl;
- (id)pathForData;
- (id)pathForSightData;
- (id)pathForTempAttachVideoData;
- (id)videoStreamForData;
```
上面这些属性和方法中`pathForSightData`是最有可能拿到小视频路径的，继续验证

```OC
(lldb) po [[[[$x0 valueForKey:@"contentObj"] mediaList] lastObject] dataUrl]
type[1], url[http://vweixinf.tc.qq.com/102/20202/snsvideodownload?filekey=30270201010420301e020166040253480410d14adcddf086f4e131d11a5b1cca1bdf0203039fa00400&bizid=1023&hy=SH&fileparam=302c0201010425302302040fde55e20204580ebd3602024eea02031e8d7d02030f42400204d970370a0201000400], enckey[0], encIdx[-1], token[]
(lldb) po [[[[$x0 valueForKey:@"contentObj"] mediaList] lastObject] pathForData]
/var/mobile/Containers/Data/Application/7C3A6322-1F57-49A0-ACDE-6EF0ED74D137/Library/WechatPrivate/6f696a1b596ce2499419d844f90418aa/wc/media/5/53/8fb0cdd77208de5b56169fb3458b45
(lldb) po [[[[$x0 valueForKey:@"contentObj"] mediaList] lastObject] pathForSightData]
/var/mobile/Containers/Data/Application/7C3A6322-1F57-49A0-ACDE-6EF0ED74D137/Library/WechatPrivate/6f696a1b596ce2499419d844f90418aa/wc/media/5/53/8fb0cdd77208de5b56169fb3458b45.mp4
(lldb) po [[[[$x0 valueForKey:@"contentObj"] mediaList] lastObject] pathForAttachVideoData]
 nil
(lldb) po [[[[$x0 valueForKey:@"contentObj"] mediaList] lastObject] videoStreamForData]
 nil
```
拿到小视频的网络url和本地路径了！这里可以用iFunBox或者scp从沙盒拷贝这个文件看看是不是这个cell应该播放的小视频。

```OC
LeonLei-MBP:~ gaoshilei$ scp root@192.168.0.115:/var/mobile/Containers/Data/Application/7C3A6322-1F57-49A0-ACDE-6EF0ED74D137/Library/WechatPrivate/6f696a1b596ce2499419d844f90418aa/wc/media/5/53/8fb0cdd77208de5b56169fb3458b45.mp4 Desktop/
8fb0cdd77208de5b56169fb3458b45.mp4                100%  232KB 231.9KB/s   00:00    
```
用QuickTime打开发现果然是我们要寻找的小视频。再验证一下url是否正确，把上面打印的dataUrl在浏览器中打开，发现也是这个小视频。分析这个类可以得出下面的结论：  

- **dataUrl：**小视频的网络url
- **pathForData：**小视频的本地路径
- **pathForSightData：**小视频的本地路径（不带后缀）

至此小视频的路径和取得方式分析已经完成，要实现转发还要继续分析微信的朋友圈发布。

##	 二、实现转发功能
###	1.“走进死胡同”
>	这节是我在找小视频转发功能时走的弯路，扒到最后并没有找到实现方法，不过也提供了一些逆向中常用的思路和方法，不想看的可以跳到第二节。  

####	（1）找到小视频拍摄完成调用的方法名称
打开小视频的拍摄界面，用cycript注入，我们要找到发布小视频的方法是哪个，然后查看当前的窗口有哪些window（因为小视频的拍摄并不是在UIApplication的keyWindow中进行的）

```OC
cy# [UIApp windows].toString()
(
    "<iConsoleWindow: 0x125f75e20; baseClass = UIWindow; frame = (0 0; 320 568); autoresize = W+H; gestureRecognizers = <NSArray: 0x125f77b70>; layer = <UIWindowLayer: 0x125df4810>>",
    "<SvrErrorTipWindow: 0x127414d40; baseClass = UIWindow; frame = (0 64; 320 45); hidden = YES; gestureRecognizers = <NSArray: 0x12740d930>; layer = <UIWindowLayer: 0x1274030b0>>",
    "<MMUIWindow: 0x127796440; baseClass = UIWindow; frame = (0 0; 320 568); gestureRecognizers = <NSArray: 0x1278083c0>; layer = <UIWindowLayer: 0x127796750>>",
    "<UITextEffectsWindow: 0x1270e0d40; frame = (0 0; 320 568); opaque = NO; autoresize = W+H; layer = <UIWindowLayer: 0x1270b4ba0>>",
    "<NewYearActionSheet: 0x127797e10; baseClass = UIWindow; frame = (0 0; 320 568); hidden = YES; userInteractionEnabled = NO; layer = <UIWindowLayer: 0x1277d5490>>"
)
```
发现当前页面一共有5个window，其中MMUIWindow是小视频拍摄所在的window，打印它的UI树状结构

```OC
cy# [#0x127796440 recursiveDescription]
```
打印结果比较长，不贴了。找到这个按钮是拍摄小视频的按钮

```OC
   |    |    |    |    |    | <UIButton: 0x1277a9d70; frame = (89.5 368.827; 141 141); opaque = NO; gestureRecognizers = <NSArray: 0x1277aaeb0>; layer = <CALayer: 0x1277a9600>>
   |    |    |    |    |    |    | <UIView: 0x1277aa0a0; frame = (0 0; 141 141); userInteractionEnabled = NO; tag = 252707333; layer = <CALayer: 0x1277aa210>>
   |    |    |    |    |    |    |    | <UIImageView: 0x1277aa2e0; frame = (0 0; 141 141); opaque = NO; userInteractionEnabled = NO; layer = <CALayer: 0x1277aa490>>
```
然后执行

```OC
cy# [#0x1277a9d70 setHidden:YES]
```
发现拍摄的按钮消失了，验证了我的猜想。寻找按钮的响应事件，可以通过target来寻找

```OC
cy# [#0x1277a9d70 allTargets]
[NSSet setWithArray:@[#"<MainFrameSightViewController: 0x1269a4600>"]]]
cy# [#0x1277a9d70 allControlEvents]
193
cy# [#0x1277a9d70 actionsForTarget:#0x1269a4600 forControlEvent:193]
null
```
发现按钮并没有对应的action，这就奇怪了！UIButton必须要有target和action，不然这个Button不能响应事件。我们试试其他的ControlEvent

```OC
cy# [#0x1277a9d70 actionsForTarget:#0x1269a4600 forControlEvent:UIControlEventTouchDown]
@["btnPress"]
cy# [#0x1277a9d70 actionsForTarget:#0x1269a4600 forControlEvent:UIControlEventTouchUpOutside]
@["btnRelease"]
cy# [#0x1277a9d70 actionsForTarget:#0x1269a4600 forControlEvent:UIControlEventTouchUpInside]
@["btnRelease"]
```
结果发现这三个ContrlEvent有对应的action，我们再看看这三个枚举的值

```OC
typedef enum UIControlEvents : NSUInteger {
    UIControlEventTouchDown = 1 <<  0,
    UIControlEventTouchDownRepeat = 1 <<  1,
    UIControlEventTouchDragInside = 1 <<  2,
    UIControlEventTouchDragOutside = 1 <<  3,
    UIControlEventTouchDragEnter = 1 <<  4,
    UIControlEventTouchDragExit = 1 <<  5,
    UIControlEventTouchUpInside = 1 <<  6,
    UIControlEventTouchUpOutside = 1 <<  7,
    UIControlEventTouchCancel = 1 <<  8,
	......
} UIControlEvents;
```
可以看出来UIControlEventTouchDown对应1，UIControlEventTouchUpInside对应128，UIControlEventTouchUpOutside对应64，三者相加正好193！原来调用`[#0x1277a9d70 allControlEvents]`的时候返回的应该是枚举，有多个枚举则把它们的值相加，是不是略坑？我也是这样觉得的！刚才我们把三种ControlEvent对应的action都打印出来了，继续LLDB+IDA进行动态分析。
####	（2）找到小视频拍摄完成跳转到发布界面的方法  
因为要找到小视频发布的方法，所以对应的`btnPress`函数我们并不关心，把重点放在`btnRelease`上面，拍摄按钮松开后就会调用的方法。在IDA中找到这个方法
![MainFrameSightViewController - (void)btnRelease](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E5%B0%8F%E8%A7%86%E9%A2%91%E8%BD%AC%E5%8F%91-btnRelease.png)  
找到之后下个断点

```OC
(lldb) br s -a 0xac000+0x10209369C
Breakpoint 4: where = WeChat`___lldb_unnamed_symbol108894$$WeChat + 32, address = 0x000000010213f69c
Process 3813 stopped
* thread #1: tid = 0xf1ef0, 0x000000010213f69c WeChat`___lldb_unnamed_symbol108894$$WeChat + 32, queue = 'com.apple.main-thread', stop reason = breakpoint 4.1
    frame #0: 0x000000010213f69c WeChat`___lldb_unnamed_symbol108894$$WeChat + 32
WeChat`___lldb_unnamed_symbol108894$$WeChat:
->  0x10213f69c <+32>: bl     0x1028d0b60               ; symbol stub for: objc_msgSend
    0x10213f6a0 <+36>: cmp    w0, #2                    ; =2 
    0x10213f6a4 <+40>: b.ne   0x10213f6dc               ; <+96>
    0x10213f6a8 <+44>: adrp   x8, 5489
```
用手机拍摄小视频然后松开，触发了断点，说明我们的猜想是正确的。继续分析发现代码是从上图的右边走的，看了一下没有什么方法是跳转到发布视频的，不过仔细看一下有一个block，是系统的延时block，位置在0x102093760。然后我们跟着断点进去，在0x1028255A0跳转到x16所存的地址

```OC
(lldb) si
Process 3873 stopped
* thread #1: tid = 0xf62c4, 0x00000001028d9598 WeChat`dispatch_after, queue = 'com.apple.main-thread', stop reason = instruction step into
    frame #0: 0x00000001028d9598 WeChat`dispatch_after
WeChat`dispatch_after:
->  0x1028d9598 <+0>: adrp   x16, 1655
    0x1028d959c <+4>: ldr    x16, [x16, #1056]
    0x1028d95a0 <+8>: br     x16

WeChat`dispatch_apply:
    0x1028d95a4 <+0>: adrp   x16, 1655
(lldb) po $x2
<__NSStackBlock__: 0x16fd49f88>
```
发现传入的参数x2是一个block，我们再回顾一下dispatch_after函数

```OC
void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
```
这个函数有三个参数，分别是dispatch_time_t、dispatch_queue_t、dispatch_block_t，那这里打印的x2就是要传入的block，所以我们猜测拍摄完小视频会有一个延时，然后执行刚才传入的block，所以x2中肯定有其他方法调用，下一步就是要知道这个block的位置。

```OC
(lldb) memory read --size 8 --format x 0x16fd49f88
0x16fd49f88: 0x000000019f8fd218 0x00000000c2000000
0x16fd49f98: 0x000000010214777c 0x0000000102fb0e60
0x16fd49fa8: 0x000000015da32600 0x000000015ea1a430
0x16fd49fb8: 0x000000015cf5fee0 0x000000016fd49ff0
```
0x000000010214777c就是block所在的位置，当然要减掉当前WeChat的ASLR偏移，最终在IDA中的地址为0x10209377C，突然发现这就是`btnRelease`的子程序sub_10209377C。这个子程序非常简单，只有一个方法`selRef_logicCheckState_`有可能是我们的目标。先看看这个方法是谁调用的

```OC
(lldb) br s -a 0xb4000+0x1020937BC
......
Process 3873 stopped
* thread #1: tid = 0xf62c4, 0x00000001021477bc WeChat`___lldb_unnamed_symbol108895$$WeChat + 64, queue = 'com.apple.main-thread', stop reason = breakpoint 3.1
    frame #0: 0x00000001021477bc WeChat`___lldb_unnamed_symbol108895$$WeChat + 64
WeChat`___lldb_unnamed_symbol108895$$WeChat:
->  0x1021477bc <+64>: adrp   x8, 5489
    0x1021477c0 <+68>: ldr    x1, [x8, #1552]
    0x1021477c4 <+72>: orr    w2, wzr, #0x1
    0x1021477c8 <+76>: ldp    x29, x30, [sp, #16]
(lldb) po $x0
<MainFrameSightViewController: 0x15d1f0c00>
```
发现还是MainFrameSightViewController这个对象调用的，那`selRef_logicCheckState_ `肯定也在这个类的头文件中，寻找一下果然发现了

```OC
- (void)logicCheckState:(int)arg1;
```
在IDA左侧窗口中寻找[MainFrameSightViewController logicCheckState:]，发现这个方法超级复杂，逻辑太多了，不着急慢慢捋。
在0x102094D6C位置我们发现一个switch jump，思路就很清晰了，我们只要找到小视频拍摄完成的这条线往下看就行了，LLDB来帮忙看看走的那条线。在0x102094D6C位置下个断点，这个断点在拍摄小视频的时候会多次触发，可以在拍摄之前把断点dis掉，拍摄松手之前再启用断点，打印此时的x8值

```OC
(lldb) p/x $x8
(unsigned long) $38 = 0x0000000102174e10
```
x8是一个指针，它指向的地址是0x102174e10，用这个地址减去当前ASLR的偏移就可以找到在IDA中的基地址，发现是0x102094E10，拍摄完成的逻辑处理这条线找到了，一直走到0x102094E24位置之后跳转0x1020951C4，这个分支的内容较少，里面有三个函数

```OC
loc_1020951C4
ADRP            X8, #selRef_hideTips@PAGE
LDR             X1, [X8,#selRef_hideTips@PAGEOFF]
MOV             X0, X19
BL              _objc_msgSend
ADRP            X8, #selRef_finishWriter@PAGE
LDR             X1, [X8,#selRef_finishWriter@PAGEOFF]
MOV             X0, X19
BL              _objc_msgSend
ADRP            X8, #selRef_turnCancelBtnForFinishRecording@PAGE
LDR             X1, [X8,#selRef_turnCancelBtnForFinishRecording@PAGEOFF]
MOV             X0, X19
BL              _objc_msgSend
B               loc_102095288
```
其中`selRef_finishWriter`和`selRef_turnCancelBtnForFinishRecording`需要重点关注，这两个方法看上去都是小视频录制结束的意思，线索极有可能就在这两个函数中。通过查看调用者发现这两个方法都属于MainFrameSightViewController，继续在IDA中查看这两个方法。在`selRef_finishWriter `中靠近末尾0x102094248的位置发现一个方法名叫做`f_switchToSendingPanel`，下个断点，然后拍摄视频，发现这个方法并没有被触发。应该不是通过这个方法调用发布界面的，继续回到`selRef_finishWriter `方法中；在0x1020941DC的位置调用方法`selRef_stopRecording`，打印它的调用者发现这个方法属于`SightFacade`，继续在IDA中寻找这个方法的实现。在这个方法的0x101F9BED4位置又调用了`selRef_stopRecord`，同样打印调用者发现这个方法属于SightCaptureLogicF4，有点像剥洋葱，继续在寻找这个方法的实现。在这个方法内部0x101A98778位置又调用了`selRef_finishWriting`，同样的原理找到这个方法是属于SightMovieWriter。已经剥了3层了，继续往下：  
在`SightMovieWriter - (void)finishWriting`中的0x10261D004位置分了两条线，这个位置下个断点，然后拍摄完小视频触发断点，打印x19的值

```OC
(lldb) po $x19
<OS_dispatch_queue: CAPTURE.CALLBACK[0x13610bcd0] = { xrefcnt = 0x4, refcnt = 0x4, suspend_cnt = 0x0, locked = 1, target = com.apple.root.default-qos.overcommit[0x1a0aa3700], width = 0x0, running = 0x0, barrier = 1 }>
```
所以代码不会跳转到loc_10261D054而是走的左侧，在左侧的代码中发现启用了一个block，这个block是子程序sub_10261D0AC，地址为0x10261D0AC，找到这个地址，结构如下图所示：
![sub_10261D0AC](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E5%B0%8F%E8%A7%86%E9%A2%91%E8%BD%AC%E5%8F%91sub_10261D0AC.png)  
可以看出来主要分两条线，我们在第一个方框的末尾也就是0x10261D108位置下个断点，等拍摄完毕触发断点之后打印x0的值为1，这里的汇编代码为

```OC
__text:000000010261D104                 CMP             X0, #2
__text:000000010261D108                 B.EQ            loc_10261D234
```
B.EQ是在上一步的结果为0才会跳转到loc_10261D234，但是这里的结果是不为0的，将x0的值改为2让上一步的结果为0

```OC
(lldb) po $x0
1
(lldb) register write $x0 2
(lldb) po $x0
2
```
此时放开断点，等待跳转到小视频发布界面，结果是一直卡在这个界面没有任何反应，所以猜测实现跳转的逻辑应该在右边的那条线，继续顺着右边的线寻找：
在右侧0x10261D3AC位置发现调用了下面的这个方法
```OC  
- (void)finishWritingWithCompletionHandler:(void (^)(void))handler;
```
这个方法是系统提供的AVAssetWriter里面的方法，在视频写入完成之后要做的操作，这个里是要传入一个block的，因为只有一个参数所以对应的变量是x2，打印x2的值

```OC
(lldb) po $x2
<__NSStackBlock__: 0x16e086c78>
(lldb) memory read --size 8 --format x 0x16e086c78
0x16e086c78: 0x00000001a0aa5218 0x00000000c2000000
0x16e086c88: 0x00000001026d94b0 0x0000000102fc98c0
0x16e086c98: 0x0000000136229fd0 0x000000016e086d00
0x16e086ca8: 0x00000001997f5318 0xfffffffec9e882ff
```  
并且通过栈内存找到block位置为0x10261D4B0（需要减去ASLR的偏移）

```OC
sub_10261D4B0
var_20= -0x20
var_10= -0x10
STP             X20, X19, [SP,#var_20]!
STP             X29, X30, [SP,#0x20+var_10]
ADD             X29, SP, #0x20+var_10
MOV             X19, X0
LDR             X0, [X19,#0x20]
ADRP            X8, #selRef_stopAmr@PAGE
LDR             X1, [X8,#selRef_stopAmr@PAGEOFF]
BL              _objc_msgSend
LDR             X0, [X19,#0x20]
ADRP            X8, #selRef_compressAudio@PAGE
LDR             X1, [X8,#selRef_compressAudio@PAGEOFF]
LDP             X29, X30, [SP,#0x20+var_10]
LDP             X20, X19, [SP+0x20+var_20],#0x20
B               _objc_msgSend
; End of function sub_10261D4B0
```
只调用了两个方法，一个是`selRef_stopAmr`停止amr（一种音频格式），另一个是`selRef_compressAudio`压缩音频，拍摄完成的下一步操作应该不会放在这两个方法里面，找了这么久也没有头绪，这个路看来走不通了，不要钻牛角尖，战略性撤退寻找其他入口。  
**逆向的乐趣就是一直寻找真相的路上，能体会到成功的乐趣，也有可能方向错了离真相反而越来越远，不要气馁调整方向继续前进！**
   
###	2.“另辟蹊径”
>（由于微信在后台偷偷升级了，下面的内容都是微信6.3.30版本的ASLR，上面的分析基于6.3.28版本）

注意到在点击朋友圈右上角的相机按钮底部会弹出一个Sheet，第一个就是Sight小视频，从这里入手，用cycript查看Sight按钮对应的事件是哪个  

```OC
iPhone-5S:~ root# cycript -p "WeChat"
cy# [UIApp windows].toString()
`(
    "<iConsoleWindow: 0x14d6ccc00; baseClass = UIWindow; frame = (0 0; 320 568); autoresize = W+H; gestureRecognizers = <NSArray: 0x14d7df110>; layer = <UIWindowLayer: 0x14d7d6f60>>",
    "<SvrErrorTipWindow: 0x14eaa5800; baseClass = UIWindow; frame = (0 0; 320 45); hidden = YES; gestureRecognizers = <NSArray: 0x14e9e8950>; layer = <UIWindowLayer: 0x14e9e6510>>",
    "<UITextEffectsWindow: 0x14ec38ba0; frame = (0 0; 320 568); opaque = NO; autoresize = W+H; layer = <UIWindowLayer: 0x14ec39360>>",
    "<UITextEffectsWindow: 0x14e9c67a0; frame = (0 0; 320 568); layer = <UIWindowLayer: 0x14d683ff0>>",
    "<UIRemoteKeyboardWindow: 0x14f226e40; frame = (0 0; 320 568); opaque = NO; autoresize = W+H; layer = <UIWindowLayer: 0x14d6f4de0>>",
    "<NewYearActionSheet: 0x14f1704a0; baseClass = UIWindow; frame = (0 0; 320 568); gestureRecognizers = <NSArray: 0x14ef9bf90>; layer = <UIWindowLayer: 0x14ef61a20>>"
)`
cy# [#0x14f1704a0 recursiveDescription].toString()
```
底部的Sheet是NewYearActionSheet，然后打印NewYearActionSheet的UI树状结构图（比较长不贴了）。然后找到Sight对应的UIButton是0x14f36d470  

```OC
cy# [#0x14f36d470 allTargets]
[NSSet setWithArray:@[#"<NewYearActionSheet: 0x14f1704a0; baseClass = UIWindow; frame = (0 0; 320 568); gestureRecognizers = <NSArray: 0x14ef9bf90>; layer = <UIWindowLayer: 0x14ef61a20>>"]]]
cy# [#0x14f36d470 allControlEvents]
64
cy# [#0x14f36d470 actionsForTarget:#0x14f1704a0 forControlEvent:64]
@["OnDefaultButtonTapped:"]
```
通过UIControl的`actionsForTarget:forControlEvent:`方法可以找到按钮绑定的事件，Sight按钮的触发方法为`OnDefaultButtonTapped:`，回到IDA中在NewYearActionSheet中找到这个方法们继续往下分析只有这个方法`selRef_dismissWithClickedButtonIndex_animated`，通过打印它的调用者发现还是NewYearActionSheet，继续点进去找到`newYearActionSheet_clickedButtonAtIndex`方法，看样子不是NewYearActionSheet自己的，打印调用者x0发现它属于类WCTimeLineViewController。跟着断点走下去在0x1012B78CC位置调用了方法`#selRef_showSightWindowForMomentWithMask_byViewController_scene`
通过观察发现这个方法的调用者是0x1012B78AC这个位置的返回值x0，这是一个类SightFacade，猜测这个方法在SightFacade里面，去头文件里找一下果然发现这个方法

```OC
- (void)showSightWindowForMomentWithMask:(id)arg1 byViewController:(id)arg2 scene:(int)arg3;
```
这个方法应该就是跳转到小视频界面的方法了。下面分别打印它的参数

```OC
(lldb) po $x2
<UIImage: 0x14f046660>, {320, 568}
(lldb) po $x3
<WCTimeLineViewController: 0x14e214800>
(lldb) po $x4
2
(lldb) po $x0
<SightFacade: 0x14f124b40>
```
其中x2、x3、x4分别对应三个参数，x0是调用者，跳到这个方法内部查看怎么实现的。发现在这个方法中进行了小视频拍摄界面的初始化工作，首先初始化一个MainFrameSightViewController，再创建一个UINavigationController将MainFrameSightViewController放进去，接下来初始化一个MMWindowController调用

```OC
- (id)initWithViewController:(id)arg1 windowLevel:(int)arg2;
```
方法将UINavigationController放了进去，完成小视频拍摄界面的所有UI创建工作。
拍摄完成之后进入发布界面，此时用cycript找到当前的Controller是SightMomentEditViewController，由此萌生一个想法，跳过前面的拍摄界面直接进入发布界面不就可以了吗？我们自己创建一个SightMomentEditViewController然后放到UINavigationController里面，然后再将这个导航控制器放到MMWindowController里面。**（这里我已经写好tweak进行了验证，具体的tweak思路编写在后文有）**结果是的确可以弹出发布的界面，但是导航栏的NavgationBar遮住了原来的，整个界面是透明的，很难看，而且发布完成之后无法销毁整个MMWindowController，还是停留在发布界面。我们要的结果不是这个，不过确实有很大的收获，最起码可以直接调用发布界面了，小视频也能正常转发。我个人猜测，当前界面不能被销毁的原因是因为MMWindowController新建了一个window,它跟TimeLine所在的keyWindow不是同一个，SightMomentEditViewController的按钮触发的方法是没有办法销毁这个window的，所以有一个大胆的猜想，我直接在当前的WCTimeLineViewController上把SightMomentEditViewController展示出来不就可以了吗？

```OC
[WCTimelineVC presentViewController:editSightVC animated:YES completion:^{
}];
```
像这样展示岂不妙哉？不过通过观察SightMomentEditViewController的头文件，结合小视频发布时界面上的元素，推测创建这个控制器至少需要两个属性，一个是小视频的路径，另一个是小视频的缩略图，将这两个关键属性给了SightMomentEditViewController那么应该就可以正常展示了  

```OC
SightMomentEditViewController *editSightVC = [[%c(SightMomentEditViewController) alloc] init];
NSString *localPath = [[self iOSREMediaItemFromSight] pathForSightData];
UIImage *image = [[self valueForKey:@"_sightView"] getImage];
[editSightVC setRealMoviePath:localPath];
[editSightVC setMoviePath:localPath];
[editSightVC setRealThumbImage:image];
[editSightVC setThumbImage:image];
[WCTimelineVC presentViewController:editSightVC animated:YES completion:^{
}];
```
小视频的发布界面可以正常显示并且所有功能都可以正常使用，唯一的问题是返回按钮没有效果，并不能销毁SightMomentEditViewController。用cycript查看左侧按钮的actionEvent找到它的响应函数是`- (void)popSelf;`，点击左侧返回触发的是pop方法，但是这个控制器并不在navgationController里面，所以无效，我们要对这个方法进行重写

```OC
- (void)popSelf
{
    [self dismissViewControllerAnimated:YES completion:^{

    }];
}
```

此时再点击返回按钮就可以正常退出了，此外，在WCContentItemViewTemplateNewSight中发现了一个方法叫做`- (void)sendSightToFriend;`，可以直接将小视频转发给好友，至此小视频转发的功能已经找到了。

##	三、代码编写及打包安装  
>	小视频的转发支持4个功能，转发至朋友圈、转发至好友、保存到本地相册、拷贝小视频链接到粘贴板。如果小视频没有下载长按只会有小视频的url链接。

###	1.越狱机（tweak安装）  
1.	新建tweak工程
2. 编写tweak文件

这里要hook两个类，分别是WCContentItemViewTemplateNewSight和SightMomentEditViewController，在WCContentItemViewTemplateNewSight中hook住onLongTouch方法然后添加menu弹出菜单，依次添加响应的方法，具体的代码如下：  

-	拷贝小视频的url链接

```OC
  NSString *localPath = [[self iOSREMediaItemFromSight] pathForSightData];
    UISaveVideoAtPathToSavedPhotosAlbum(localPath, nil, nil, nil);
}
```

-	保存小视频到本地相册

```OC
NSString *localPath = [[self iOSREMediaItemFromSight] pathForSightData];
    UISaveVideoAtPathToSavedPhotosAlbum(localPath, nil, nil, nil);
```

-	转发到朋友圈

```OC
 SightMomentEditViewController *editSightVC = [[%c(SightMomentEditViewController) alloc] init];
    NSString *localPath = [[self iOSREMediaItemFromSight] pathForSightData];
    UIImage *image = [[self valueForKey:@"_sightView"] getImage];
    [editSightVC setRealMoviePath:localPath];
    [editSightVC setMoviePath:localPath];
    [editSightVC setRealThumbImage:image];
    [editSightVC setThumbImage:image];
    [WCTimelineVC presentViewController:editSightVC animated:YES completion:^{

    }];
```

-	转发给好友

```OC
[self sendSightToFriend];
```

-	长按手势

```OC
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    if (menuController.isMenuVisible) return;//防止出现menu闪屏的情况
    [self becomeFirstResponder];
    NSString *localPath = [[self iOSREMediaItemFromSight] pathForSightData];
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
    [menuController setTargetRect:CGRectZero inView:self];
    [menuController setMenuVisible:YES animated:YES];
```

具体的tweak文件我放在了github上[WCSightRetweet](https://github.com/gaoshilei/WCSightRetweet)

3.	编写WCTimelineRetweet.h头文件
编写这个头文件的目的是防止tweak在编译期间报错，我们可以在编写好tweak试着编译一下，然后根据报错信息来添加这个头文件的内容，在这个文件中要声明在tweak我们用到的微信的类和方法，具体请看代码：  

```OC
@interface WCUrl : NSObject
@property(retain, nonatomic) NSString *url;
@end
@interface WCContentItem : NSObject
@property(retain, nonatomic) NSMutableArray *mediaList;
@end
@interface WCDataItem : NSObject
@property(retain, nonatomic) WCContentItem *contentObj;
@end
@interface WCMediaItem : NSObject
@property(retain, nonatomic) WCUrl *dataUrl;
- (id)pathForSightData;
@end
@interface MMServiceCenter : NSObject
+ (id)defaultCenter;
- (id)getService:(Class)arg1;
@end
@interface WCFacade : NSObject
- (id)getTimelineDataItemOfIndex:(long long)arg1;
@end
@interface WCSightView : UIView
- (id)getImage;
@end
@interface WCContentItemViewTemplateNewSight : UIView{
    WCSightView *_sightView;
}
- (WCMediaItem *)iOSREMediaItemFromSight;
- (void)iOSREOnSaveToDisk;
- (void)iOSREOnCopyURL;
- (void)sendSightToFriend;
@end
@interface SightMomentEditViewController : UIViewController
@property(retain, nonatomic) NSString *moviePath;
@property(retain, nonatomic) NSString *realMoviePath;
@property(retain, nonatomic) UIImage *thumbImage;
@property(retain, nonatomic) UIImage *realThumbImage;
- (void)makeInputController;
@end
@interface MMWindowController : NSObject
- (id)initWithViewController:(id)arg1 windowLevel:(int)arg2;
- (void)showWindowAnimated:(_Bool)arg1;
@end
@interface WCTimeLineViewController : UIViewController
- (long long)calcDataItemIndex:(long long)arg1;
@end
@interface MMTableViewCell : UIView
@end
@interface MMTableView : UIView
- (id)indexPathForCell:(id)cell;
@end
```  
4.	Makefile文件修改

```OC
THEOS_DEVICE_IP = 192.168.0.115//手机所在的IP
include $(THEOS)/makefiles/common.mk
ARCHS = arm64//支持的CPU架构
TWEAK_NAME = WCTimelineSightRetweet
WCTimelineSightRetweet_FILES = Tweak.xm
WCTimelineSightRetweet_FRAMEWORKS = UIKit CoreGraphics//导入系统的framework
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"//安装完成杀掉的进程
```
control文件不需要做修改，然后执行命令`make package install`安装到手机，微信会被杀掉，然后再次打开微信转发小视频的功能已经加上了。  

###	2.非越狱机微信重签名安装  
####	准备工作
#####	（1）	安装iOSOpenDev  
1.  安装 [macports](https://www.macports.org/install.php) (安装过程需要连接VPN,否则无法安装成功)

2.  安装完MacPorts后打开终端，输入 `sudo port -v selfupdate` 更新MacPorts到最新版本，时间可能比较长。

3.  更新完MacPorts后安装DPKG文件，在终端输入`sudo port -f install dpkg`

4.  下载安装 [iOSOpendev](http://iosopendev.com/download) 如果安装失败，可以通过 `Command + L` 查看安装中出现的问题。

```OC
PackageKit: Install Failed: Error Domain=PKInstallErrorDomain Code=112 "运行软件包“iOSOpenDev-1.6-2.pkg”的脚本时出错。" UserInfo={NSFilePath=./postinstall, NSURL=file://localhost/Users/ice/Downloads/iOSOpenDev-1.6-2.pkg#iodsetup.pkg, PKInstallPackageIdentifier=com.iosopendev.iosopendev162.iod-setup.pkg, NSLocalizedDescription=运行软件包“iOSOpenDev-1.6-2.pkg”的脚本时出错。} {
        NSFilePath = "./postinstall";
        NSLocalizedDescription = "\U8fd0\U884c\U8f6f\U4ef6\U5305\U201ciOSOpenDev-1.6-2.pkg\U201d\U7684\U811a\U672c\U65f6\U51fa\U9519\U3002";
        NSURL = "file://localhost/Users/ice/Downloads/iOSOpenDev-1.6-2.pkg#iodsetup.pkg";
        PKInstallPackageIdentifier = "com.iosopendev.iosopendev162.iod-setup.pkg";
    }
```  
这里有一个解决方案：下载[iOSOpenDevInstallSolve](https://github.com/gaoshilei/iOSOpenDevInstallSolve)中的Specifications文件夹   
5.  修复安装失败问题  
打开步骤4下载的Specifications文件夹，里面应该有8个文件,如果你有安装多个xcode注意放到对应的xcode里面。  
（1）iPhoneOS开头的四个文件放到/应用程序/Xcode/Content/Developer/Platforms/IphoneOS.platform/Developer/Library/Xcode/Specifications文件夹下（如果没有，请自己创建一个Specifications文件夹）  
（2）iPhone Simulator 开头的另外四个文件放入/应用程序/Xcode/Content/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Specifications文件夹下(如果没有，请同样创建一个)  
（3）在/应用程序/Xcode/Content/Developer/Platforms/iPhoneSimulator.platform/Developer/文件夹下创建usr文件夹，usr文件夹下再创建一个名为bin的文件夹。  
**注意：有时候会提示安装失败，打开Xcode新建工程，如果在工程的选项菜单中有iOSOpenDev就表示安装成功了，不用管那个安装提示。**  

#####	（2）	安装ideviceinstaller
>	安装ipa包用的，也可以通过itool之类的工具，不过ideviceinstaller可以看到安装过程的过程，方便我们找到出错原因。

执行命令

```OC
brew install ideviceinstaller
```
如果提示brew命令找不到，那就是你的Mac还没有安装[Homebrew](http://brew.sh/index_zh-cn.html)  
常见的报错信息：  

```OC
ERROR: Could not connect to lockdownd, error code -5
```
这个时候只要重新安装libimobiledevice就可以了（因为ideviceinstaller依赖很多其他插件）  
执行下面的命令：

```OC
$   brew uninstall libimobiledevice
$   brew install --HEAD libimobiledevice
```

下载[iOS App Signer](https://github.com/DanTheMan827/ios-app-signer)重签名工具*（省去很多命令行操作，一键重签名！）*  

（3）	下载砸壳的微信应用
>	因为AppStore的包是被加密（有壳），无法进行重签名，所以要用砸壳的，可以用dumpdecrypted自己砸壳，也可以直接利用PP助手或者itool助手下载越狱版已经砸过壳的微信应用。  

（4）	安装yololib  
yololib可以将dylib注入进WeChat二进制文件中，这样才能是你的Hook有作用，下载之后编译得到[yololib](https://github.com/gaoshilei/yololib)

####	代码注入以及打包安装 

#####（1）生成静态库  
在上一步中已经安装好iOSOpendev，此时打开Xcode新建项目，在选择工程界面会出现iOSOpendev的工程，这里我们要选择CaptainHook Tweak项目
![iOSOpenDev](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E9%87%8D%E7%AD%BE%E5%90%8DiOSDev.png)
新建好的工程只有一个.mm文件，我们只需要把所有hook方法写在这个文件中即可。  
因为非越狱机不能像越狱机一样可以安装tweak插件对原来的应用进行hook，CaptainHook使用的Runtime机制实现，利用宏命令封装类定义、方法替换等功能，简单介绍它的使用方法：  

1.	hook某个类
 
```OC
CHDeclareClass(WCContentItemViewTemplateNewSight); 
```
`CHDeclareClass(ClassName)`表示要hook哪个类，一般写在对这个类操作的最前面。

2.	在hook的类种新建方法  

```OC
CHDeclareMethod0(id, WCContentItemViewTemplateNewSight, SLSightDataItem){......}
```
`CHDeclareMethod(count, return_type, class_type, name1, arg1, ....)`表示新建一个方法，count表示这个方法的参数个数，return_type表示返回类型，class_type填写这个方法所在的类名，name1表示方法名，arg1表示第一个参数，如果没有参数则不填，以此类推。  

3.	hook原来的方法  

```OC
CHOptimizedMethod0(self, void, WCContentItemViewTemplateNewSight, onLongTouch){
CHSuper(0, className, Method);//可选
......
}
```
`CHOptimizedMethod(count, optimization, return_type, class_type, name1, type1, arg1)` 表示hook原来的方法（如果不加`CHSuper(0, className, Method)`表示复写原来的方法，CHSuper表示在当前位置调用原来的方法实现），count表示hook的方法参数个数，optimization一般填self，return_type即方法返回值类型，class_type填当前类的类名，name1是方法名，arg1是参数，如果没有参数不同填写arg，以此类推。  

4.	构造函数

```OC
CHConstructor
{
    @autoreleasepool
    {
        CHLoadLateClass(WCContentItemViewTemplateNewSight);
        CHHook(0, WCContentItemViewTemplateNewSight, onLongTouch);    
     }
}
```
这是CaptainHook的入口函数，所有被hook的类必须在这里声明加载，类里面的方法要在这里声明hook。  
然后就可以往类和方法中写代码了，代码太长不贴了，我放在了github上面[MMPlugin](https://github.com/gaoshilei/MMPlugin)  
**这个项目中包含了小视频转发、自动抢红包、修改微信运动步数功能，自动抢红包和修改微信运动步数功能可以手动关闭。**
>	注意：如果用到了系统的类记住要导入相应的类库（比方说UIKit）和头文件否则编译的时候会报错。

编译成功之后就可以在Products文件夹中找到编译好的静态库了  
![编译好的静态库](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E9%87%8D%E7%AD%BE%E5%90%8D-%E7%BC%96%E8%AF%91%E5%A5%BD%E7%9A%84%E9%9D%99%E6%80%81%E5%BA%93.png)  
在finder中找到它，拷贝出来待用。
#####	(2)	签名+打包+安装  
进行到这里目前应该有的材料有：

-	砸壳的微信app    
- 	编译好的MMPlugin.dylib
-  安装好的iOS App Signer
-  编译好的yololib文件  
-  ideviceinstaller

从原来的微信app中找到WeChat二进制文件拷贝出来待用，**删除weChat.app中的Watch文件夹、PlugIns文件夹中的WeChatShareExtensionNew.appex**。  
执行下面的命令将MMPlugin.dylib注入到WeChat二进制文件中，命令如下：

```shell
LeonLei-MBP:WeChat gaoshilei$ ./yololib WeChat MMPlugin.dylib
```
**执行这个命令时要确保yololib、WeChat、WeChat.app处于同一目录下。** 

完成之后将MMPlugin.dylib和WeChat拷贝到原来的WeChat.app中，覆盖掉原来的WeChat文件。  
打开iOS App Signer按照下图选择好各项参数：
![iOS App Signer](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E9%87%8D%E7%AD%BE%E5%90%8D-iOSAppSigner.png)  
我这里选择的是企业级证书，个人开发者证书也是可以的，一定要选择生产环境的，选好之后点击start，稍等片刻一个经过重签名的ipa包就生成了。  
连上你的手机执行下面的命令查看ideviceinstaller是否连接上手机：

```shell
LeonLei-MBP:WeChat gaoshilei$ ideviceinfo
```
如果打印出一大堆手机的信息表示连接成功可以安装ipa包，如果不成功请根据错误提示进行调整。执行下面的命令进行安装：  

```shell
LeonLei-MBP:WeChat gaoshilei$ ideviceinstaller -i WeChat.ipa 
WARNING: could not locate iTunesMetadata.plist in archive!
WARNING: could not locate Payload/WeChat.app/SC_Info/WeChat.sinf in archive!
Copying 'WeChat.ipa' to device... DONE.
Installing 'com.xxxxxxxxxxxx'
 - CreatingStagingDirectory (5%)
 - ExtractingPackage (15%)
 - InspectingPackage (20%)
 - TakingInstallLock (20%)
 - PreflightingApplication (30%)
 - InstallingEmbeddedProfile (30%)
 - VerifyingApplication (40%)
 - CreatingContainer (50%)
 - InstallingApplication (60%)
 - PostflightingApplication (70%)
 - SandboxingApplication (80%)
 - GeneratingApplicationMap (90%)
 - Complete
```
安装完成，在手机上打开微信试试我们添加的新功能吧！如果某个环节卡住会报错，请根据报错信息进行修改。请看效果图：  
![小视频转发](http://oeat6c2zg.bkt.clouddn.com/%E5%BE%AE%E4%BF%A1%E9%87%8D%E7%AD%BE%E5%90%8D-%E5%B0%8F%E8%A7%86%E9%A2%91%E8%BD%AC%E5%8F%91%E6%95%88%E6%9E%9C%E5%9B%BE.jpg)  

####	有任何问题请在文章评论区留言，或者在博客首页点击邮件联系我。
