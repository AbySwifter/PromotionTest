//
//  CommonCode.h
//  Pods
//
//  Created by aby.wang on 2019/12/20.
//

#ifndef CommonCode_h
#define CommonCode_h

#ifndef weakify
#if DEBUG
#if __has_feature(objc_arc)
#define weakify(object) autoreleasepool{} __weak __typeof__(object) weak##_##object = object;
#else
#define weakify(object) autoreleasepool{} __block __typeof__(object) block##_##object = object;
#endif
#else
#if __has_feature(objc_arc)
#define weakify(object) try{} @finally{} {} __weak __typeof__(object) weak##_##object = object;
#else
#define weakify(object) try{} @finally{} {} __block __typeof__(object) block##_##object = object;
#endif
#endif
#endif

#ifndef strongify
#if DEBUG
#if __has_feature(objc_arc)
#define strongify(object) autoreleasepool{} __typeof__(object) object = weak##_##object;
#else
#define strongify(object) autoreleasepool{} __typeof__(object) object = block##_##object;
#endif
#else
#if __has_feature(objc_arc)
#define strongify(object) try{} @finally{} __typeof__(object) object = weak##_##object;
#else
#define strongify(object) try{} @finally{} __typeof__(object) object = block##_##object;
#endif
#endif
#endif

// 错误码
#define SUCCESS_CODE 6000

#define PROMOTION_PHONE_ID_KEY @"device_id"
#define PROMOTION_BUNDLE_ID_KEY @"bundle_id"
#define PROMOTION_DEVICE_NAME_KEY @"device_info"

#define PROMOTION_TOKEN_KEY @"PROMOTION_TOKEN_KEY"
#define PROMOTION_TOKEN_EXPIRED_KEY @"TOKEN_EXPIRED_KEY"
#define PROMOTION_APP_KEY @"app_key"
#define PROMOTION_DEBUG_KEY @"debug"

#define PROMOTION_DEBUG_STORE_KEY @"LAST_DEBUG_STATE"

#define PROMOTION_LOGIN @"/login/binding"
#define REGISTER_PATH @"/limit/api/sdk/register"
#define UPLOAD_INFO_PATH @"/limit/api/sdk/device/info"
#define PROMOTION_PATH @"/limit/api/sdk/promotion/self"

#endif /* CommonCode_h */
