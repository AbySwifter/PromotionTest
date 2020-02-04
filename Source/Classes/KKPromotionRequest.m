//
//  KKPromotionRequest.m
//  KKPromotion
//
//  Created by aby.wang on 2019/12/19.
//

#import "KKPromotionRequest.h"
#import "KKPromotion.h"

#define PROMOTION_BASE_URL @"http://rap2api.taobao.org/app/mock/240360"

NSString * AFPercentEscapedStringFromString(NSString *string) {
    static NSString * const kAFCharactersGeneralDelimitersToEncode = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
    static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";
    
    NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowedCharacterSet removeCharactersInString:[kAFCharactersGeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];
    
    // FIXME: https://github.com/AFNetworking/AFNetworking/pull/3028
    // return [string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
    
    static NSUInteger const batchSize = 50;
    
    NSUInteger index = 0;
    NSMutableString *escaped = @"".mutableCopy;
    
    while (index < string.length) {
        NSUInteger length = MIN(string.length - index, batchSize);
        NSRange range = NSMakeRange(index, length);
        
        // To avoid breaking up character sequences such as 👴🏻👮🏽
        range = [string rangeOfComposedCharacterSequencesForRange:range];
        
        NSString *substring = [string substringWithRange:range];
        NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
        [escaped appendString:encoded];
        
        index += range.length;
    }
    
    return escaped;
}

@interface AFQueryStringPair : NSObject
@property (readwrite, nonatomic, strong) id field;
@property (readwrite, nonatomic, strong) id value;

- (instancetype)initWithField:(id)field value:(id)value;

- (NSString *)URLEncodedStringValue;
@end

@implementation AFQueryStringPair

- (instancetype)initWithField:(id)field value:(id)value {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.field = field;
    self.value = value;
    
    return self;
}

- (NSString *)URLEncodedStringValue {
    if (!self.value || [self.value isEqual:[NSNull null]]) {
        return AFPercentEscapedStringFromString([self.field description]);
    } else {
        return [NSString stringWithFormat:@"%@=%@", AFPercentEscapedStringFromString([self.field description]), AFPercentEscapedStringFromString([self.value description])];
    }
}

@end

FOUNDATION_EXPORT NSArray * AFQueryStringPairsFromDictionary(NSDictionary *dictionary);
FOUNDATION_EXPORT NSArray * AFQueryStringPairsFromKeyAndValue(NSString *key, id value);

NSArray * AFQueryStringPairsFromDictionary(NSDictionary *dictionary) {
    return AFQueryStringPairsFromKeyAndValue(nil, dictionary);
}

NSArray * AFQueryStringPairsFromKeyAndValue(NSString *key, id value) {
    NSMutableArray *mutableQueryStringComponents = [NSMutableArray array];
    
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(compare:)];
    
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = value;
        // Sort dictionary keys to ensure consistent ordering in query string, which is important when deserializing potentially ambiguous sequences, such as an array of dictionaries
        for (id nestedKey in [dictionary.allKeys sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            id nestedValue = dictionary[nestedKey];
            if (nestedValue) {
                [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue((key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey), nestedValue)];
            }
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        for (id nestedValue in array) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue([NSString stringWithFormat:@"%@[]", key], nestedValue)];
        }
    } else if ([value isKindOfClass:[NSSet class]]) {
        NSSet *set = value;
        for (id obj in [set sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(key, obj)];
        }
    } else {
        [mutableQueryStringComponents addObject:[[AFQueryStringPair alloc] initWithField:key value:value]];
    }
    
    return mutableQueryStringComponents;
}

NSString * AFQueryStringFromParameters(NSDictionary *parameters) {
    NSMutableArray *mutablePairs = [NSMutableArray array];
    for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
        [mutablePairs addObject:[pair URLEncodedStringValue]];
    }
    return [mutablePairs componentsJoinedByString:@"&"];
}


@interface KKPromotionRequest ()

@property(nonatomic, strong)NSURLSession* session;
@property(nonatomic, strong, readonly)NSSet<NSString *> *HTTPMethodsEncodingParametersInURI;

@end


@implementation KKPromotionRequest

-(NSSet<NSString *> *)HTTPMethodsEncodingParametersInURI{
    return [[NSSet alloc] initWithArray:@[@"GET"]];
}

-(NSURLSession *)session{
    if (!_session) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    }
    return _session;
}

-(void)requestWithPath:(NSString*)path method:(PromotionRequestMethod)method parameters:(NSDictionary *)params completion:(RequestCallBack)callback{
    
    dispatch_queue_t global = dispatch_get_global_queue(0, 0);
    dispatch_async(global, ^{
        NSString *urlString = [NSString stringWithFormat:@"%@%@", PROMOTION_BASE_URL, path];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            return;
        }
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30];
        request.HTTPMethod = [self methodString:method];
        NSString *token = [[KKPromotion sharedInstance] currentToken];
        if (token) {
            [request setValue:token forHTTPHeaderField:@"token"];
        }
        [request setValue:@"application/json;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
        request = [self requestBySerializingRequest:request params:params];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSURLSessionDataTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            callback(error, data);
        }];
        [task resume];
    });
}

- (NSMutableURLRequest *)requestBySerializingRequest:(NSMutableURLRequest *)request params:(NSDictionary *)params{
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[request.HTTPMethod uppercaseString]]) {
        NSString *query = nil;
        query = AFQueryStringFromParameters(params);
        if (query && query.length > 0) {
            mutableRequest.URL = [NSURL URLWithString:[[mutableRequest.URL absoluteString] stringByAppendingFormat:mutableRequest.URL.query ? @"&%@" : @"?%@", query]];
        }
    } else {
        if (params) {
            if ([NSJSONSerialization isValidJSONObject:params]) {
                NSError *serializationError = nil;
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:NSJSONWritingPrettyPrinted error:&serializationError];
                if (serializationError) {
                    NSLog(@"参数数据转化有误：%@",serializationError.localizedFailureReason);
                } else {
                    // 设置初始参数
                    [mutableRequest setHTTPBody:jsonData];
                }
            } else {
                NSLog(@"参数有误");
            }
        }
    }
    return mutableRequest;
}

#pragma mark - 私有方法
- (NSString *)methodString:(PromotionRequestMethod)method{
    NSString *result = @"get";
    switch (method) {
        case PromotionRequestPost:
            result = @"post";
            break;
        case PromotionRequestGet:
            result = @"get";
            break;
        case PromotionRequestDelete:
            result = @"put";
            break;
        default:
            break;
    }
    return result;
}

@end
