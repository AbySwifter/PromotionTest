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
    [KKPromotion setAppKey:@"your app key"];
    [[KKPromotion sharedInstance] promotionLaunchWithCompletion:^(BOOL success, BOOL isFirst) {
        NSLog(@"是否加载成功%d, 是否为第一次加载%d", success, isFirst);
    }];
}


@end
