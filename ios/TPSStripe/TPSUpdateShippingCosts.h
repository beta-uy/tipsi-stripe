//
//  TPSUpdateShippingCosts.h
//  TPSStripe
//
//  Created by Carolina Aitcin on 12/11/17.
//  Copyright © 2017 Tipsi. All rights reserved.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface TPSUpdateShippingCosts : RCTEventEmitter <RCTBridgeModule>

+ (void)fetchShippingCosts:(NSString *)countryCode stateCode:(NSString *)stateCode;

@end
