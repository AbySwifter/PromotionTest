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

#define PROMOTION_TOKEN_KEY @"PROMOTION_TOKEN_KEY"
#define PROMOTION_TOKEN_EXPIRED_KEY @"TOKEN_EXPIRED_KEY"
#define PROMOTION_APP_KEY @"app_key"
#define PROMOTION_DEBUG_KEY @"debug"

#define PROMOTION_DEBUG_STORE_KEY @"LAST_DEBUG_STATE"

#define REGISTER_PATH @"/api/sdk/register"
#define UPLOAD_INFO_PATH @"/api/sdk/device/info"
#define PROMOTION_PATH @"/api/sdk/promotion/self"

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
            NSError *error = [NSError errorWithDomain:@"custom" code:6000 userInfo:@{
                NSLocalizedDescriptionKey: [result objectForKey:@"message"] ? [result objectForKey:@"message"] : @"未知错误"
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
    BOOL tokenExpired = [self checkTokenExpired];
    BOOL isIDChanged = [self checkPhoneIdentifierChanged];
    self.completion = completion;
    if (!tokenExist) {
        // 注册
        [self registerDevice];
    } else if (tokenExpired) {
        // 重新登录
        [self registerDevice];
    } else if (isIDChanged) {
        // 重新注册
        [self registerDevice];
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
    NSString* phoneIdentifier = [KKPromotion getPhoneIdentifier];
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
    NSString* phoneIdentifier = [KKPromotion getPhoneIdentifier];
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
            NSDictionary* dataDic = result[@"data"];
            @strongify(self)
            [self saveRegisterInfo:dataDic];
            [self updateDeviceInfo];
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
    NSNumber *number = [registerInfo objectForKey:@"expired"];
    double expiredDate = [number doubleValue];
    if (expiredDate != 0.0) {
        self.expiredTime = expiredDate;
        [[NSUserDefaults standardUserDefaults] setValue:@(expiredDate) forKey:PROMOTION_TOKEN_EXPIRED_KEY];
        NSLog(@"------存储过期时间");
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([number integerValue] == SUCCESS_CODE) {
                if (self.completion) {
                    self.completion(YES, self.isFirstRegister);
                }
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
    NSString* phoneIdentifier = [KKPromotion getPhoneIdentifier];
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

/// 检查token是否过期
- (BOOL)checkTokenExpired{
    // 获取当前时间, 单位毫秒
    NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970 * 1000;
    return currentTime > self.expiredTime;
}

/// 设备id是否发生变化
- (BOOL)checkPhoneIdentifierChanged{
    NSString *oldPhoneIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:PROMOTION_PHONE_ID_KEY];
    NSString *currentPhoneIdentifier = [KKPromotion getPhoneIdentifier];
    return ![currentPhoneIdentifier isEqualToString:oldPhoneIdentifier];
}

#pragma mark - 参数准备
- (NSDictionary *)getLaunchInfo{
    NSMutableDictionary* params = [NSMutableDictionary dictionary];
    // 当前版本号
    NSString* localAppVersion = [KKPromotion getLocalApperVersion];
    [params setObject:localAppVersion forKey:@"version_code"];
    // 当前国家
    NSString* country = [KKPromotion getCountryName];
    [params setObject:country forKey:@"country"];
    // 当前语言
    NSString* language = [KKPromotion getPreferredLanguage];
    [params setObject:language forKey:@"language"];
    // 当前系统版本号
    NSString* osVersion = [KKPromotion systemName];
    [params setObject:osVersion forKey:@"os_version"];
    // 当前设备idfa
    NSString* phoneIdentifier = [KKPromotion getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    return params;
}

/// 每次安装只获取一次的参数
- (NSDictionary *)getOnceInfo{
    NSMutableDictionary* params = [NSMutableDictionary dictionary];
    // 当前bundle id
    NSString* bundleIdentifier = [KKPromotion getBundleID];
    [params setObject:bundleIdentifier forKey:PROMOTION_BUNDLE_ID_KEY];
    // 当前设备名称
    NSString* deviceName = [KKPromotion currentPhoneName];
    [params setObject:deviceName forKey:PROMOTION_DEVICE_NAME_KEY];
    // 当前设备idfa
    NSString* phoneIdentifier = [KKPromotion getPhoneIdentifier];
    [params setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    // 设置AppID
    if (self.appKey) {
        [params setObject:self.appKey forKey:PROMOTION_APP_KEY];
    }
    [params setObject:@(self.isDebug ? 1 : 0) forKey:PROMOTION_DEBUG_KEY];
    return params;
}

#pragma mark - 设备信息获取
+ (NSString *)getLocalApperVersion{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
}

+ (NSString *)getBundleID{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
}

+ (NSString *)getCountryName{
    // iOS 获取设备当前地区的代码
    NSString *localeIdentifier = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    return localeIdentifier;
}

+ (NSString *)getPreferredLanguage{
    // iOS 获取设备当前语言的代码
    NSString *preferredLanguageCode = [[NSLocale preferredLanguages] firstObject];
    return preferredLanguageCode;
}

/// 获取系统名
+ (NSString *)systemName{
    NSString *phoneVersion = [[UIDevice currentDevice] systemVersion];
    NSString *phoneName = [[UIDevice currentDevice] systemName];
    return [NSString stringWithFormat:@"%@ %@",phoneName, phoneVersion];
}

+ (NSString *)getPhoneIdentifier{
    BOOL isIDFAActive = [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];
    NSString *phoneIdentifier = nil;
    if (isIDFAActive) {
        phoneIdentifier = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    } else {
        phoneIdentifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    }
    [[NSUserDefaults standardUserDefaults] setObject:phoneIdentifier forKey:PROMOTION_PHONE_ID_KEY];
    return phoneIdentifier;
}

#pragma mark - 设备名映射
+ (NSString *)currentPhoneName {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *platform = [NSString stringWithCString:systemInfo.machine encoding:NSASCIIStringEncoding];
    if ([platform isEqualToString:@"iPhone1,1"]) return @"iPhone 2G";
    
    if ([platform isEqualToString:@"iPhone1,2"]) return @"iPhone 3G";
    
    if ([platform isEqualToString:@"iPhone2,1"]) return @"iPhone 3GS";
    
    if ([platform isEqualToString:@"iPhone3,1"]) return @"iPhone 4";
    
    if ([platform isEqualToString:@"iPhone3,2"]) return @"iPhone 4";
    
    if ([platform isEqualToString:@"iPhone3,3"]) return @"iPhone 4";
    
    if ([platform isEqualToString:@"iPhone4,1"]) return @"iPhone 4S";
    
    if ([platform isEqualToString:@"iPhone5,1"]) return @"iPhone 5";
    
    if ([platform isEqualToString:@"iPhone5,2"]) return @"iPhone 5";
    
    if ([platform isEqualToString:@"iPhone5,3"]) return @"iPhone 5c";
    
    if ([platform isEqualToString:@"iPhone5,4"]) return @"iPhone 5c";
    
    if ([platform isEqualToString:@"iPhone6,1"]) return @"iPhone 5s";
    
    if ([platform isEqualToString:@"iPhone6,2"]) return @"iPhone 5s";
    
    if ([platform isEqualToString:@"iPhone7,1"]) return @"iPhone 6 Plus";
    
    if ([platform isEqualToString:@"iPhone7,2"]) return @"iPhone 6";
    
    if ([platform isEqualToString:@"iPhone8,1"]) return @"iPhone 6s";
    
    if ([platform isEqualToString:@"iPhone8,2"]) return @"iPhone 6s Plus";
    
    if ([platform isEqualToString:@"iPhone8,4"]) return @"iPhone SE";
    
    if ([platform isEqualToString:@"iPhone9,1"]) return @"iPhone 7";//国行、日版、港行
    
    if ([platform isEqualToString:@"iPhone9,2"]) return @"iPhone 7 Plus";//港行、国行
    if ([platform isEqualToString:@"iPhone9,3"])    return @"iPhone 7";//美版、台版
    if ([platform isEqualToString:@"iPhone9,4"])    return @"iPhone 7 Plus";//美版、台版
    
    if ([platform isEqualToString:@"iPhone10,1"])   return @"iPhone 8";//国行(A1863)、日行(A1906)
    
    if ([platform isEqualToString:@"iPhone10,4"])   return @"iPhone 8";//美版(Global/A1905)
    
    if ([platform isEqualToString:@"iPhone10,2"])   return @"iPhone 8 Plus";//国行(A1864)、日行(A1898)
    
    if ([platform isEqualToString:@"iPhone10,5"])   return @"iPhone 8 Plus";//美版(Global/A1897)
    
    if ([platform isEqualToString:@"iPhone10,3"])   return @"iPhone X";//国行(A1865)、日行(A1902)
    
    if ([platform isEqualToString:@"iPhone10,6"])   return @"iPhone X";//美版(Global/A1901)
    
    
    if ([platform isEqualToString:@"iPhone12,1"])   return @"iPhone 11";
    
    if ([platform isEqualToString:@"iPhone12,3"])   return @"iPhone 11 Pro";
    
    if ([platform isEqualToString:@"iPhone12,5"])   return @"iPhone 11 Pro Max";
    
    
    if ([platform isEqualToString:@"iPod1,1"])   return @"iPod Touch 1G";
    
    if ([platform isEqualToString:@"iPod2,1"])   return @"iPod Touch 2G";
    
    if ([platform isEqualToString:@"iPod3,1"])   return @"iPod Touch 3G";
    
    if ([platform isEqualToString:@"iPod4,1"])   return @"iPod Touch 4G";
    
    if ([platform isEqualToString:@"iPod5,1"])   return @"iPod Touch 5G";
    
    if ([platform isEqualToString:@"iPad1,1"])   return @"iPad 1G";
    
    if ([platform isEqualToString:@"iPad2,1"])   return @"iPad 2";
    
    if ([platform isEqualToString:@"iPad2,2"])   return @"iPad 2";
    
    if ([platform isEqualToString:@"iPad2,3"])   return @"iPad 2";
    
    if ([platform isEqualToString:@"iPad2,4"])   return @"iPad 2";
    
    if ([platform isEqualToString:@"iPad2,5"])   return @"iPad Mini 1G";
    
    if ([platform isEqualToString:@"iPad2,6"])   return @"iPad Mini 1G";
    
    if ([platform isEqualToString:@"iPad2,7"])   return @"iPad Mini 1G";
    
    if ([platform isEqualToString:@"iPad3,1"])   return @"iPad 3";
    
    if ([platform isEqualToString:@"iPad3,2"])   return @"iPad 3";
    
    if ([platform isEqualToString:@"iPad3,3"])   return @"iPad 3";
    
    if ([platform isEqualToString:@"iPad3,4"])   return @"iPad 4";
    
    if ([platform isEqualToString:@"iPad3,5"])   return @"iPad 4";
    
    if ([platform isEqualToString:@"iPad3,6"])   return @"iPad 4";
    
    if ([platform isEqualToString:@"iPad4,1"])   return @"iPad Air";
    
    if ([platform isEqualToString:@"iPad4,2"])   return @"iPad Air";
    
    if ([platform isEqualToString:@"iPad4,3"])   return @"iPad Air";
    
    if ([platform isEqualToString:@"iPad4,4"])   return @"iPad Mini 2G";
    
    if ([platform isEqualToString:@"iPad4,5"])   return @"iPad Mini 2G";
    
    if ([platform isEqualToString:@"iPad4,6"])   return @"iPad Mini 2G";
    
    if ([platform isEqualToString:@"i386"])      return @"iPhone Simulator";
    
    if ([platform isEqualToString:@"x86_64"])    return @"iPhone Simulator";
    
    return platform;
}

@end
