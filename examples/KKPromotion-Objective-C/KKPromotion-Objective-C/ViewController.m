//
//  ViewController.m
//  KKPromotion-Objective-C
//
//  Created by aby on 2020/2/4.
//  Copyright © 2020 aby. All rights reserved.
//

#import "ViewController.h"
#import "KKPromotion.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
}

- (IBAction)register:(UIButton *)sender {
    [KKPromotion setAppKey:@"177993460746624"];
    [[KKPromotion sharedInstance] promotionLaunchWithCompletion:^(BOOL success, BOOL isFirst) {
        NSLog(@"是否加载成功%d, 是否为第一次加载%d", success, isFirst);
    }];
}

- (IBAction)pushtoken:(id)sender {
    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

- (IBAction)getPromotionInfo:(id)sender {
    [[KKPromotion sharedInstance] requestPromotionWithKey:@"homepage" complete:^(NSError * _Nullable error, NSString * _Nullable json) {
        NSLog(@"%@", json);
    }];
}

- (IBAction)setUserPayState:(id)sender {
    [[KKPromotion sharedInstance] setUserPayState:true];
}

- (IBAction)setUserlevel:(id)sender {
    [[KKPromotion sharedInstance] setUserLevel:1];
}


@end
