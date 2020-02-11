//
//  PromotionController.m
//  KKPromotion
//
//  Created by aby on 2020/2/10.
//

#import "PromotionController.h"
#if COCOPODS
#import <kkPromotion.h>
#else
#import "KKPromotion.h"
#endif

@implementation PromotionController

+ (instancetype)instance{
    static PromotionController *manager=nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [PromotionController new];
    });
    return manager;
}

/// 设置后台应用ID
/// @param appKey 应用ID
-(void)setAppKey:(NSString *)appKey{
    [KKPromotion setAppKey:appKey];
}

/// 打开sandbox环境
+ (void)enableDebug:(BOOL)isDebug{
    [KKPromotion enableDebug:isDebug];
}

/// 匿名注册/登录设备
- (void)promotionLaunch{
    [[KKPromotion sharedInstance] promotionLaunchWithCompletion:^(BOOL success, BOOL isFirst) {
        NSDictionary* result = @{
            @"key": @"registerCallback",
            @"status": [NSString stringWithFormat:@"%d", success],
            @"data": [NSString stringWithFormat:@"%d", isFirst]
        };
        NSString* resultString = [self dictionaryToJson:result];
        [self sendMessage:resultString];
    }];
}

/// 设置用户付费状态
/// @param isPay 是否付费
- (void)setUserPayState:(BOOL)isPay{
    [[KKPromotion sharedInstance] setUserPayState:isPay];
}

/// 设置用户等级
- (void)setUserLevel:(NSInteger)level{
    [[KKPromotion sharedInstance] setUserLevel:level];
}

/// 请求远程配置的自推广信息
/// @param key 自推广键
- (void)requestPromotionWithKey:(NSString *)key {
    [[KKPromotion sharedInstance] requestPromotionWithKey:key complete:^(NSError * _Nullable error, id  _Nullable json) {
        NSString* errorString = error == nil ? @"" : error.localizedFailureReason;
        NSString* jsonString = @"";
        if ([NSJSONSerialization isValidJSONObject:json]) {
            if ([json isKindOfClass:[NSDictionary class]]) {
                jsonString = [self dictionaryToJson:json];
            }
            if ([json isKindOfClass:[NSArray class]]) {
                jsonString = [self arrayToJson:json];
            }
        }
        NSDictionary* result = @{
            @"key": @"promotionParams",
            @"status": errorString,
            @"data": jsonString
        };
        [self sendMessage:[self dictionaryToJson:result]];
    }];
}

- (NSString*)arrayToJson:(NSArray *)array{
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:array options:NSJSONWritingPrettyPrinted error:&parseError];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString*)dictionaryToJson:(NSDictionary *)dic{
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:&parseError];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)sendMessage:(NSString *)message{
#ifdef RUN_WITH_UNITY
    UnitySendMessage("PromotionManager", "Callback", [message UTF8String]);
#endif
    
#ifdef RUN_WITH_LAYA
//  [[conchRuntime GetIOSConchRuntime]callbackToJSWithObject:self methodName:@"initMopub:" ret:message];
#endif
}

extern "C"{
    void setAPPKey(char *appkey) {
        NSString* appkeyString = [NSString stringWithUTF8String:appkey];
        [[PromotionController instance] setAppKey:appkeyString];
    }
    
    void launchAndRegister() {
        [[PromotionController instance] promotionLaunch];
    }
    
    void setUserPayState(bool isPay) {
        [[PromotionController instance] setUserPayState:isPay];
    }

    void setUserLevel(int level) {
        [[PromotionController instance] setUserLevel:level];
    }

    void requestPromotion(char *key) {
        NSString* keyString = [NSString stringWithUTF8String:key];
        [[PromotionController instance] requestPromotionWithKey:keyString];
    }
}

@end
