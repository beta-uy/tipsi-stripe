//
//  TPSUpdateShippingCost.m
//  TPSStripe
//
//  Created by Carolina Aitcin on 12/11/17.
//  Copyright © 2017 Tipsi. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TPSUpdateShippingCosts.h"

NSString *const FetchShippingCosts = @"FetchShippingCosts";
static Boolean hasListeners = NO;

@implementation TPSUpdateShippingCosts
//{
//    bool hasListeners;
//}
//
// Will be called when this module's first listener is added.
-(void)startObserving {
    hasListeners = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fetchShippingCostsEvent:)
                                                 name:FetchShippingCosts
                                               object:nil];
    // Set up any upstream listeners or background tasks as necessary
}

-(void)stopObserving {
    hasListeners = NO;
    // Remove upstream listeners, stop unnecessary background tasks
}


RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"FetchShippingCosts"];
}

+ (void)fetchShippingCosts:(NSString *)countryCode stateCode:(NSString *)stateCode
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FetchShippingCosts object:@{@"countryCode": countryCode, @"stateCode": stateCode}];
}

- (void)fetchShippingCostsEvent:(NSNotification *)notification
{
     if (notification.object) {
         [self sendEventWithName:@"FetchShippingCosts" body:notification.object];
     }
}

@end
