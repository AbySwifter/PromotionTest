//
//  KKViewController.m
//  KKPromotion
//
//  Created by wyx96553@163.com on 12/17/2019.
//  Copyright (c) 2019 wyx96553@163.com. All rights reserved.
//

#import "KKViewController.h"
#import <KKPromotion/KKPromotion.h>
#import <UserNotifications/UserNotifications.h>

@interface KKViewController ()

@end

@implementation KKViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)registerAction:(UIButton *)sender {
    
}


- (IBAction)openNotification:(id)sender {
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionBadge| UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] registerForRemoteNotifications];
                });
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            });
        }
    }];
}

- (IBAction)setUserPayInfomation:(id)sender {
    [[KKPromotion sharedInstance] setUserPayState:YES];
}

- (IBAction)setUserLevel:(id)sender {
    [[KKPromotion sharedInstance] setUserLevel:400];
}
- (IBAction)requestPromotionInfo:(id)sender {
    [[KKPromotion sharedInstance] requestPromotionWithKey:@"key" complete:^(NSError * _Nullable error, NSString * _Nullable json) {
        NSLog(@"-----错误信息: %@", error.localizedDescription);
        NSLog(@"-----结果: %@", json);
    }];
}

@end
