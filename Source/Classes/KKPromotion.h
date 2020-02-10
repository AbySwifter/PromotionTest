//
//  KKPromotion.h
//  KKPromotion
//
//  Created by aby.wang on 2019/12/17.
//

#import <Foundation/Foundation.h>

#define PROMOTION_BUNDLE_ID_KEY @"bundle_id"
#define PROMOTION_DEVICE_NAME_KEY @"device_info"
#define PROMOTION_PHONE_ID_KEY @"device_id"



NS_ASSUME_NONNULL_BEGIN

typedef void(^RegisterCallback)(BOOL success, BOOL isFirst);
typedef void(^PromotionCallback)(NSError * _Nullable error, NSString * _Nullable json);

NS_SWIFT_NAME(Promotion)
@interface KKPromotion : NSObject

@property(nonatomic, strong, readonly, nullable)NSString* currentToken;

/// 设置后台应用ID
/// @param appKey 应用ID
+ (void)setAppKey:(NSString *)appKey;

/// 打开sandbox环境
+ (void)enableDebug:(BOOL)isDebug;

/// 获取实例对象
+ (instancetype)sharedInstance;

/// 匿名注册/登录设备
/// @param completion 完成回调
- (void)promotionLaunchWithCompletion:(RegisterCallback)completion NS_SWIFT_NAME(launchDevice(completion:));

/// 上传推送token
/// @param deviceToken 推送token
- (void)updatePushToken:(NSData *)deviceToken;

/// 设置用户付费状态
/// @param isPay 是否付费
- (void)setUserPayState:(BOOL)isPay;

/// 设置用户等级
/// @param level 等级
- (void)setUserLevel:(NSInteger)level;

/// 推送其他信息
/// @param otherInfo 符合json的字段
- (void)updateOtherInfo:(NSDictionary<NSString *, id> *)otherInfo;

/// 请求远程配置的自推广信息
/// @param key 自推广键
/// @param complete 结果
- (void)requestPromotionWithKey:(NSString *)key complete:(PromotionCallback)complete;

@end

NS_ASSUME_NONNULL_END
