//
//  PromotionTool.h
//  KKPromotion
//
//  Created by aby on 2020/2/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PromotionTool : NSObject

+ (NSString *)getLocalApperVersion;

+ (NSString *)getBundleID;

+ (NSString *)getCountryName;

+ (NSString *)getPreferredLanguage;

/// 获取系统名
+ (NSString *)systemName;

+ (NSString *)getPhoneIdentifier;

+ (NSString *)currentPhoneName;

@end

NS_ASSUME_NONNULL_END
