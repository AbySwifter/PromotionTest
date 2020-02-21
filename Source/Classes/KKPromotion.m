//
//  KKPromotion.m
//  KKPromotion
//
//  Created by aby.wang on 2019/12/17.
//
#import <UIKit/UIKit.h>
#import "KKPromotion.h"
#import <sys/utsname.h>
#import <AdSupport/AdSupport.h>
#import "KKPromotionRequest.h"
#import "CommonCode.h"
#import "PromotionTool.h"



@interface KKPromotion ()

@property(nonatomic, strong)NSString *token;
@property(nonatomic, assign)NSTimeInterval expiredTime;
@property(nonatomic, strong)KKPromotionRequest *request;

@property(nonatomic, copy)RegisterCallback completion;

@property(nonatomic, assign)BOOL isFirstRegister;

@property(nonatomic, strong)NSString* appKey;
@property(nonatomic, assign)BOOL isDebug;

@end

@implementation KKPromotion

+ (void)setAppKey:(NSString *)appKey{
    [KKPromotion sharedInstance].appKey =  appKey;
}

+ (void)enableDebug:(BOOL)isDebug{
#if DEBUG
    [KKPromotion sharedInstance].isDebug = isDebug;
    BOOL lastStatus = [[NSUserDefaults standardUserDefaults] boolForKey:PROMOTION_DEBUG_STORE_KEY];
    // 如果不相等，说明测试环境下，开发者手动更改了模式。需要重新注册用户。
    if (lastStatus != isDebug) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PROMOTION_TOKEN_KEY];
        [[NSUserDefaults standardUserDefaults] setBool:isDebug forKey:PROMOTION_DEBUG_STORE_KEY];
    }
#endif
}

#pragma mark - 初始化相关方法
+ (instancetype)sharedInstance{
    static KKPromotion* manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[KKPromotion alloc] init];
#if DEBUG
        manager.isDebug =  YES;
#endif
    });
    return manager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.token = [[NSUserDefaults standardUserDefaults] stringForKey:PROMOTION_TOKEN_KEY];
        self.expiredTime = [[NSUserDefaults standardUserDefaults] doubleForKey:PROMOTION_TOKEN_EXPIRED_KEY];
        self.isFirstRegister = self.token == nil;
    }
    return self;
}

-(KKPromotionRequest *)request{
    if (!_request) {
        _request = [[KKPromotionRequest alloc] init];
    }
    return _request;
}

- (NSString *)currentToken{
    return self.token;
}

#pragma mark - 自推广广告信息请求
- (void)requestPromotionWithKey:(NSString *)key complete:(PromotionCallback)complete{
    
    [self.request requestWithPath:PROMOTION_PATH method:PromotionRequestGet parameters:@{@"key": key} completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(error, nil);
            });
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError* error = [NSError errorWithDomain:@"com.framework.kkPromotion" code:4001 userInfo:@{NSLocalizedDescriptionKey: @"返回数据解析类型有误"}];
                complete(error, nil);
            });
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        if ([number integerValue] == SUCCESS_CODE) {
            id resultDic = [result objectForKey:@"data"];
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(nil, resultDic);
            });
        } else {
           NSError *error = [NSError errorWithDomain:@"custom" code:[number integerValue] userInfo:@{
               NSLocalizedDescriptionKey: [result objectForKey:@"msg"] ? [result objectForKey:@"msg"] : @"网络请求成功，没有解析到配置数据"
           }];
           dispatch_async(dispatch_get_main_queue(), ^{
               complete(error, nil);
           });
        }
    }];
}

#pragma mark - 匿名用户注册流程
- (void)promotionLaunchWithCompletion:(RegisterCallback)completion{
    // 检查token是否存下
    BOOL tokenExist = [self checkTokenExist];
    BOOL isIDChanged = [self checkPhoneIdentifierChanged];
    self.completion = completion;
    if (!tokenExist) {
        // 注册
//        [self registerDevice];
        [self getTokenFromRemote];
    } else if (isIDChanged) {
        // 重新注册
        [self getTokenFromRemote];
    } else {
        // 上报设备相关信息
        [self updateDeviceInfo];
    }
}

- (void)updatePushToken:(NSData *)deviceToken{
    if (deviceToken) {
        if ([UIDevice currentDevice].systemVersion.floatValue < 13.0) {
            NSString *token = [[deviceToken description] stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString:@"<>"]];
            token = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
            [self updatePushTokenInfo:token];
        } else {
            // Fallback on earlier versions
            if (![deviceToken isKindOfClass:[NSData class]]) return;
            const unsigned *tokenBytes = [deviceToken bytes];
            NSString *hexToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                                  ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                                  ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                                  ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
            [self updatePushTokenInfo:hexToken];
        }
    }
}

- (void)setUserLevel:(NSInteger)level{
    // 上报其他信息
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    // 当前设备idfa
    NSString* phoneIdentifier = [PromotionTool getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    [params setObject:@(level) forKey:@"user_level"];
    [self.request requestWithPath:UPLOAD_INFO_PATH method:PromotionRequestPost parameters:params completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        //        @strongify(self)
        if (error) {
            NSLog(@"网络请求错误");
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            NSLog(@"------ 上传用户等级失败");
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        if ([number integerValue] == SUCCESS_CODE) {
            NSLog(@"------ 上传用户等级成功");
        } else {
            NSLog(@"------ 上传用户等级失败");
        }
    }];
}

- (void)setUserPayState:(BOOL)isPay{
    // 上报其他信息
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    // 当前设备idfa
    NSString* phoneIdentifier = [PromotionTool getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    [params setObject:@(isPay ? 1 : 0) forKey:@"user_pay_state"];
    [self.request requestWithPath:UPLOAD_INFO_PATH method:PromotionRequestPost parameters:params completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        //        @strongify(self)
        if (error) {
            NSLog(@"网络请求错误:%@", error.localizedFailureReason);
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        if ([number integerValue] == SUCCESS_CODE) {
            NSLog(@"------ 上传用户购买信息成功");
        } else {
            NSLog(@"------ 上传用户购买信息级失败");
        }
    }];
}

- (void)updateOtherInfo:(NSDictionary<NSString *, id> *)otherInfo{
    [self.request requestWithPath:UPLOAD_INFO_PATH method:PromotionRequestPost parameters:@{@"other_info": otherInfo} completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        //        @strongify(self)
        if (error) {
            NSLog(@"网络请求错误");
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            NSLog(@"------ 上传其他字段失败");
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        if ([number integerValue] == SUCCESS_CODE) {
            NSLog(@"------ 上传其他字段成功");
        } else {
            NSLog(@"------ 上传其他字段失败");
        }
    }];
}

#pragma mark - 私有方法
-(void)getTokenFromRemote{
    NSDictionary* params = @{@"bind-id": [PromotionTool getPhoneIdentifier], @"app-id": [PromotionTool getBundleID]};
    @weakify(self)
    [self.request requestWithPath:PROMOTION_LOGIN method:PromotionRequestPost urlParams:params parameters:@{} completion:^(NSError * _Nullable error, id  _Nullable responseObject) {
        if (error) {
            NSLog(@"网络请求错误");
            if (self.completion) {
                self.completion(NO, self.isFirstRegister);
            }
            return;
        }
        if (responseObject && [responseObject isKindOfClass:[NSDictionary class]]) {
            NSDictionary* result = responseObject;
            NSDictionary* dataDic = result[@"data"];
            NSNumber* number = [result objectForKey:@"code"];
            if ([number integerValue] == SUCCESS_CODE) {
                @strongify(self)
                [self saveRegisterInfo:dataDic];
                [self registerDevice];
            } else {
                NSLog(@"获取授权失败");
            }
        } else {
            NSLog(@"网络结果有误");
        }
    }];
}

- (void)registerDevice {
    @weakify(self)
    // 注册用户
    [self.request requestWithPath:REGISTER_PATH method:PromotionRequestPost parameters:[self getOnceInfo] completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        if (error) {
            NSLog(@"网络请求错误");
            if (self.completion) {
                self.completion(NO, self.isFirstRegister);
            }
            return;
        }
        if (responseObject && [responseObject isKindOfClass:[NSDictionary class]]) {
            NSDictionary* result = responseObject;
            NSNumber* number = [result objectForKey:@"code"];
            NSInteger resultCode = [number integerValue];
            if ([number integerValue] == SUCCESS_CODE) {
                @strongify(self)
                [self updateDeviceInfo];
            } if ([number integerValue] == 8005 ||resultCode == 8009 || resultCode == 8002) {
                [self getTokenFromRemote];
            }
        } else {
            NSLog(@"网络结果有误");
        }
    }];
}

- (void)saveRegisterInfo:(nonnull NSDictionary *)registerInfo{
    NSString* token = [registerInfo objectForKey:@"token"];
    if (token && ![token isEqualToString:@""]) {
        self.token = token;
        [[NSUserDefaults standardUserDefaults] setValue:token forKey:PROMOTION_TOKEN_KEY];
        NSLog(@"------存储token信息");
    }
}

- (void)updateDeviceInfo {
    @weakify(self)
    // 上报其他信息
    [self.request requestWithPath:UPLOAD_INFO_PATH method:PromotionRequestPost parameters:[self getLaunchInfo] completion:^(NSError * _Nullable error, id _Nullable responseObject) {
        @strongify(self)
        if (error) {
            NSLog(@"网络请求错误");
            self.completion(NO, self.isFirstRegister);
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.completion) {
                    self.completion(NO, self.isFirstRegister);
                }
            });
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        NSInteger resultCode = [number integerValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (resultCode == SUCCESS_CODE) {
                if (self.completion) {
                    self.completion(YES, self.isFirstRegister);
                }
            } else if (resultCode == 8005 ||resultCode == 8009 || resultCode == 8002) {
                [self getTokenFromRemote];
            } else {
                if (self.completion) {
                    self.completion(NO, self.isFirstRegister);
                }
            }
        });
    }];
}

- (void)updatePushTokenInfo:(NSString *)tokenStr{
//    @weakify(self)
    // 上报其他信息
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    // 当前设备idfa
    NSString* phoneIdentifier = [PromotionTool getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    [params setObject:tokenStr forKey:@"push_token"];
    [self.request requestWithPath:UPLOAD_INFO_PATH method:PromotionRequestPost parameters:params completion:^(NSError * _Nullable error, id _Nullable responseObject) {
//        @strongify(self)
        if (error) {
            NSLog(@"网络请求错误");
            return;
        }
        if (![responseObject isKindOfClass:[NSDictionary class]]) {
            NSLog(@"------ 上传推送令牌失败");
            return;
        }
        NSDictionary* result = responseObject;
        NSNumber* number = [result objectForKey:@"code"];
        if ([number integerValue] == SUCCESS_CODE) {
            NSLog(@"------ 上传推送令牌成功");
        } else {
            NSLog(@"------ 上传推送令牌失败");
        }
    }];
}

#pragma mark - 初始状态判断
/// 检查token是否存在
- (BOOL)checkTokenExist{
    return self.token != nil;
}

/// 设备id是否发生变化
- (BOOL)checkPhoneIdentifierChanged{
    NSString *oldPhoneIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:PROMOTION_PHONE_ID_KEY];
    NSString *currentPhoneIdentifier = [PromotionTool getPhoneIdentifier];
    return ![currentPhoneIdentifier isEqualToString:oldPhoneIdentifier];
}

#pragma mark - 参数准备
- (NSDictionary *)getLaunchInfo{
    NSMutableDictionary* params = [NSMutableDictionary dictionary];
    // 当前版本号
    NSString* localAppVersion = [PromotionTool getLocalApperVersion];
    [params setObject:localAppVersion forKey:@"version_code"];
    // 当前国家
    NSString* country = [PromotionTool getCountryName];
    [params setObject:country forKey:@"country"];
    // 当前语言
    NSString* language = [PromotionTool getPreferredLanguage];
    [params setObject:language forKey:@"language"];
    // 当前系统版本号
    NSString* osVersion = [PromotionTool systemName];
    [params setObject:osVersion forKey:@"os_version"];
    // 当前设备idfa
    NSString* phoneIdentifier = [PromotionTool getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    return params;
}

/// 每次安装只获取一次的参数
- (NSDictionary *)getOnceInfo{
    NSMutableDictionary* params = [NSMutableDictionary dictionary];
    // 当前bundle id
    NSString* bundleIdentifier = [PromotionTool getBundleID];
    [params setObject:bundleIdentifier forKey:PROMOTION_BUNDLE_ID_KEY];
    // 当前设备名称
    NSString* deviceName = [PromotionTool currentPhoneName];
    [params setObject:deviceName forKey:PROMOTION_DEVICE_NAME_KEY];
    // 当前设备idfa
    NSString* phoneIdentifier = [PromotionTool getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    // 设置AppID
    if (self.appKey) {
        [params setObject:self.appKey forKey:PROMOTION_APP_KEY];
    }
    [params setObject:@(self.isDebug ? 1 : 0) forKey:PROMOTION_DEBUG_KEY];
    return params;
}

#pragma mark - 设备信息获取


@end
