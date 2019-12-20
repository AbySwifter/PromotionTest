//
//  KKPromotionRequest.h
//  KKPromotion
//
//  Created by aby.wang on 2019/12/19.
//

#import <Foundation/Foundation.h>

typedef enum : NSUInteger {
    PromotionRequestPost,
    PromotionRequestGet,
    PromotionRequestDelete,
} PromotionRequestMethod;

typedef void(^RequestCallBack)( NSError * _Nullable error,  NSData * _Nullable data);

NS_ASSUME_NONNULL_BEGIN

@interface KKPromotionRequest : NSObject

-(void)requestWithPath:(NSString*)path method:(PromotionRequestMethod)method parameters:(NSDictionary *)params completion:(RequestCallBack)callback;
@end

NS_ASSUME_NONNULL_END
