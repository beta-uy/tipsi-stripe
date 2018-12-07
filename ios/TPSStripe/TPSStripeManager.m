//
//  TPSStripeManager.m
//  TPSStripe
//
//  Created by Anton Petrov on 28.10.16.
//  Copyright © 2016 Tipsi. All rights reserved.
//

#import "TPSStripeManager.h"
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>

#import "TPSUpdateShippingCosts.h"
#import "TPSError.h"

@implementation RCTConvert (STPBankAccountHolderType)

RCT_ENUM_CONVERTER(STPBankAccountHolderType,
                   (@{
                      @"individual": @(STPBankAccountHolderTypeIndividual),
                      @"company": @(STPBankAccountHolderTypeCompany),
                      }),
                   STPBankAccountHolderTypeCompany,
                   integerValue)

+ (NSString *)STPBankAccountHolderTypeString:(STPBankAccountHolderType)type {
    NSString *string = nil;
    switch (type) {
        case STPBankAccountHolderTypeCompany: {
            string = @"company";
        }
            break;
        case STPBankAccountHolderTypeIndividual:
        default: {
            string = @"individual";
        }
            break;
    }
    return string;
}

@end

@implementation RCTConvert (STPBankAccountStatus)

RCT_ENUM_CONVERTER(STPBankAccountStatus,
                   (@{
                      @"new": @(STPBankAccountStatusNew),
                      @"validated": @(STPBankAccountStatusValidated),
                      @"verified": @(STPBankAccountStatusVerified),
                      @"errored": @(STPBankAccountStatusErrored),
                      }),
                   STPBankAccountStatusNew,
                   integerValue)

+ (NSString *)STPBankAccountStatusString:(STPBankAccountStatus)status {
    NSString *string = nil;
    switch (status) {
        case STPBankAccountStatusValidated: {
            string = @"validated";
        }
            break;
        case STPBankAccountStatusVerified: {
            string = @"verified";
        }
            break;
        case STPBankAccountStatusErrored: {
            string = @"errored";
        }
            break;
        case STPBankAccountStatusNew:
        default: {
            string = @"new";
        }
            break;
    }
    return string;
}

@end

NSString * const TPSPaymentNetworkAmex = @"american_express";
NSString * const TPSPaymentNetworkDiscover = @"discover";
NSString * const TPSPaymentNetworkMasterCard = @"master_card";
NSString * const TPSPaymentNetworkVisa = @"visa";

@implementation TPSStripeManager
{
    NSString *publishableKey;
    NSString *merchantId;
    
    RCTPromiseResolveBlock promiseResolver;
    RCTPromiseRejectBlock promiseRejector;
    
    BOOL requestIsCompleted;
    NSMutableArray<PKPaymentSummaryItem *> *summaryItemsApplePay;
    NSMutableArray *countriesApplepay;
    
    void (^applePayCompletion)(PKPaymentAuthorizationStatus);
    void (^shippingContactUpdateCompletion)(PKPaymentRequestShippingContactUpdate *update);
    void (^shippingContactUpdateCompletionDeprecate)(PKPaymentAuthorizationStatus status, NSArray<PKShippingMethod *> *shippingMethods, NSArray<PKPaymentSummaryItem *> *summaryItems);
}

- (instancetype)init {
    if ((self = [super init])) {
        requestIsCompleted = YES;
    }
    return self;
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSDictionary *)constantsToExport
{
    return @{
             @"TPSErrorDomain": TPSErrorDomain,
             @"TPSErrorCodeApplePayNotConfigured": [@(TPSErrorCodeApplePayNotConfigured) stringValue],
             @"TPSErrorCodePreviousRequestNotCompleted": [@(TPSErrorCodePreviousRequestNotCompleted) stringValue],
             @"TPSErrorCodeUserCancel": [@(TPSErrorCodeUserCancel) stringValue],
             };
}


RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(init:(NSDictionary *)options) {
    publishableKey = options[@"publishableKey"];
    merchantId = options[@"merchantId"];
    [Stripe setDefaultPublishableKey:publishableKey];
}

RCT_EXPORT_METHOD(deviceSupportsApplePay:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@([PKPaymentAuthorizationViewController canMakePayments]));
}

RCT_EXPORT_METHOD(canMakeApplePayPayments:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSArray <NSString *> *paymentNetworksStrings =
    options[@"networks"] ?: [TPSStripeManager supportedPaymentNetworksStrings];
    
    NSArray <PKPaymentNetwork> *networks = [self paymentNetworks:paymentNetworksStrings];
    resolve(@([PKPaymentAuthorizationViewController canMakePaymentsUsingNetworks:networks]));
}

RCT_EXPORT_METHOD(completeApplePayRequest:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    promiseResolver = resolve;
    
    if (applePayCompletion) {
        applePayCompletion(PKPaymentAuthorizationStatusSuccess);
    }
}

RCT_EXPORT_METHOD(cancelApplePayRequest:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    promiseResolver = resolve;
    
    if (applePayCompletion) {
        applePayCompletion(PKPaymentAuthorizationStatusFailure);
    }
}

RCT_EXPORT_METHOD(createTokenWithCard:(NSDictionary *)params
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if(!requestIsCompleted) {
        NSError *error = [TPSError previousRequestNotCompletedError];
        reject([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
        return;
    }
    
    requestIsCompleted = NO;
    
    STPCardParams *cardParams = [[STPCardParams alloc] init];
    
    [cardParams setNumber: params[@"number"]];
    [cardParams setExpMonth: [params[@"expMonth"] integerValue]];
    [cardParams setExpYear: [params[@"expYear"] integerValue]];
    [cardParams setCvc: params[@"cvc"]];
    
    [cardParams setCurrency: params[@"currency"]];
    [cardParams setName: params[@"name"]];
    [cardParams setAddressLine1: params[@"addressLine1"]];
    [cardParams setAddressLine2: params[@"addressLine2"]];
    [cardParams setAddressCity: params[@"addressCity"]];
    [cardParams setAddressState: params[@"addressState"]];
    [cardParams setAddressCountry: params[@"addressCountry"]];
    [cardParams setAddressZip: params[@"addressZip"]];
    
    [[STPAPIClient sharedClient] createTokenWithCard:cardParams completion:^(STPToken *token, NSError *error) {
        requestIsCompleted = YES;
        
        if (error) {
            reject(nil, nil, error);
        } else {
            resolve([self convertTokenObject:token]);
        }
    }];
}

RCT_EXPORT_METHOD(createTokenWithBankAccount:(NSDictionary *)params
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if(!requestIsCompleted) {
        NSError *error = [TPSError previousRequestNotCompletedError];
        reject([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
        return;
    }
    
    requestIsCompleted = NO;
    
    STPBankAccountParams *bankAccount = [[STPBankAccountParams alloc] init];
    
    [bankAccount setAccountNumber: params[@"accountNumber"]];
    [bankAccount setCountry: params[@"countryCode"]];
    [bankAccount setCurrency: params[@"currency"]];
    [bankAccount setRoutingNumber: params[@"routingNumber"]];
    [bankAccount setAccountHolderName: params[@"accountHolderName"]];
    STPBankAccountHolderType accountHolderType =
    [RCTConvert STPBankAccountHolderType:params[@"accountHolderType"]];
    [bankAccount setAccountHolderType: accountHolderType];
    
    [[STPAPIClient sharedClient] createTokenWithBankAccount:bankAccount completion:^(STPToken *token, NSError *error) {
        requestIsCompleted = YES;
        
        if (error) {
            reject(nil, nil, error);
        } else {
            resolve([self convertTokenObject:token]);
        }
    }];
}

RCT_EXPORT_METHOD(paymentRequestWithCardForm:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if(!requestIsCompleted) {
        NSError *error = [TPSError previousRequestNotCompletedError];
        reject([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
        return;
    }
    
    requestIsCompleted = NO;
    // Save promise handlers to use in `paymentAuthorizationViewController`
    promiseResolver = resolve;
    promiseRejector = reject;
    
    NSUInteger requiredBillingAddressFields = [self billingType:options[@"requiredBillingAddressFields"]];
    NSString *companyName = options[@"companyName"] ? options[@"companyName"] : @"";
    BOOL smsAutofillDisabled = [options[@"smsAutofillDisabled"] boolValue];
    STPUserInformation *prefilledInformation = [self userInformation:options[@"prefilledInformation"]];
    NSString *managedAccountCurrency = options[@"managedAccountCurrency"];
    NSString *nextPublishableKey = options[@"publishableKey"] ? options[@"publishableKey"] : publishableKey;
    UIModalPresentationStyle formPresentation = [self formPresentation:options[@"presentation"]];
    STPTheme *theme = [self formTheme:options[@"theme"]];
    
    STPPaymentConfiguration *configuration = [[STPPaymentConfiguration alloc] init];
    [configuration setRequiredBillingAddressFields:requiredBillingAddressFields];
    [configuration setCompanyName:companyName];
    [configuration setSmsAutofillDisabled:smsAutofillDisabled];
    [configuration setPublishableKey:nextPublishableKey];
    
    
    STPAddCardViewController *addCardViewController = [[STPAddCardViewController alloc] initWithConfiguration:configuration theme:theme];
    [addCardViewController setDelegate:self];
    [addCardViewController setPrefilledInformation:prefilledInformation];
    [addCardViewController setManagedAccountCurrency:managedAccountCurrency];
    // STPAddCardViewController must be shown inside a UINavigationController.
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:addCardViewController];
    [navigationController setModalPresentationStyle:formPresentation];
    navigationController.navigationBar.stp_theme = theme;
    [RCTPresentedViewController() presentViewController:navigationController animated:YES completion:nil];
}

RCT_EXPORT_METHOD(paymentRequestWithApplePay:(NSArray *)items
                  withOptions:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if(!requestIsCompleted) {
        NSError *error = [TPSError previousRequestNotCompletedError];
        reject([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
        return;
    }
    
    requestIsCompleted = NO;
    // Save promise handlers to use in `paymentAuthorizationViewController`
    promiseResolver = resolve;
    promiseRejector = reject;
    
    NSUInteger requiredShippingAddressFields = [self applePayAddressFields:options[@"requiredShippingAddressFields"]];
    NSUInteger requiredBillingAddressFields = [self applePayAddressFields:options[@"requiredBillingAddressFields"]];
    PKShippingType shippingType = [self applePayShippingType:options[@"shippingType"]];
    NSMutableArray *shippingMethodsItems = options[@"shippingMethods"] ? options[@"shippingMethods"] : [NSMutableArray array];
    NSMutableArray *countries = options[@"countries"] ? options[@"countries"] : [NSMutableArray array];
    countriesApplepay = countries;
    NSString* currencyCode = options[@"currencyCode"] ? options[@"currencyCode"] : @"USD";
    
    NSMutableArray *shippingMethods = [NSMutableArray array];
    
    for (NSDictionary *item in shippingMethodsItems) {
        PKShippingMethod *shippingItem = [[PKShippingMethod alloc] init];
        shippingItem.label = item[@"label"];
        shippingItem.detail = item[@"detail"];
        shippingItem.amount = [NSDecimalNumber decimalNumberWithString:item[@"amount"]];
        shippingItem.identifier = item[@"id"];
        [shippingMethods addObject:shippingItem];
    }
    
    NSMutableArray *summaryItems = [NSMutableArray array];
    
    for (NSDictionary *item in items) {
        PKPaymentSummaryItem *summaryItem = [[PKPaymentSummaryItem alloc] init];
        summaryItem.label = item[@"label"];
        summaryItem.amount = [NSDecimalNumber decimalNumberWithString:item[@"amount"]];
        [summaryItems addObject:summaryItem];
    }
    
    summaryItemsApplePay = summaryItems;
    PKPaymentRequest *paymentRequest = [Stripe paymentRequestWithMerchantIdentifier:merchantId];
    
    [paymentRequest setRequiredShippingAddressFields:requiredShippingAddressFields];
    [paymentRequest setRequiredBillingAddressFields:requiredBillingAddressFields];
    [paymentRequest setPaymentSummaryItems:summaryItems];
    [paymentRequest setShippingMethods:shippingMethods];
    [paymentRequest setShippingType:shippingType];
    [paymentRequest setCurrencyCode:currencyCode];
    
    //    [paymentRequest setSupportedCountries:(NSSet<NSString *> * _Nullable)];
    
    //http://nshipster.com/apple-pay/
    if ([Stripe canSubmitPaymentRequest:paymentRequest]) {
        PKPaymentAuthorizationViewController *paymentAuthorizationVC = [[PKPaymentAuthorizationViewController alloc] initWithPaymentRequest:paymentRequest];
        paymentAuthorizationVC.delegate = self;
        [RCTPresentedViewController() presentViewController:paymentAuthorizationVC animated:YES completion:nil];
    } else {
        // There is a problem with your Apple Pay configuration.
        promiseRejector = nil;
        promiseResolver = nil;
        requestIsCompleted = YES;
        
        NSError *error = [TPSError applePayNotConfiguredError];
        reject([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
    }
}

RCT_EXPORT_METHOD(openApplePaySetup) {
    PKPassLibrary *library = [[PKPassLibrary alloc] init];
    
    // Here we should check, if openPaymentSetup selector exist
    if ([library respondsToSelector:NSSelectorFromString(@"openPaymentSetup")]) {
        [library openPaymentSetup];
    }
}

#pragma mark STPAddCardViewControllerDelegate

- (void)addCardViewController:(STPAddCardViewController *)controller
               didCreateToken:(STPToken *)token
                   completion:(STPErrorBlock)completion {
    [RCTPresentedViewController() dismissViewControllerAnimated:YES completion:nil];
    
    requestIsCompleted = YES;
    completion(nil);
    promiseResolver([self convertTokenObject:token]);
}

- (void)addCardViewControllerDidCancel:(STPAddCardViewController *)addCardViewController {
    [RCTPresentedViewController() dismissViewControllerAnimated:YES completion:nil];
    
    if (!requestIsCompleted) {
        requestIsCompleted = YES;
        NSError *error = [TPSError userCancelError];
        promiseRejector([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
    }
    
}

#pragma mark Beta TopNine

RCT_EXPORT_METHOD(updateApplePayShippingMethod:(NSArray *)shippingMethodsItems
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    NSMutableArray *shippingMethods = [NSMutableArray array];
    for (NSDictionary *item in shippingMethodsItems) {
        PKShippingMethod *shippingItem = [[PKShippingMethod alloc] init];
        shippingItem.label = item[@"label"];
        shippingItem.detail = item[@"detail"];
        shippingItem.amount = [NSDecimalNumber decimalNumberWithString:item[@"amount"]];
        shippingItem.identifier = item[@"id"];
        [shippingMethods addObject:shippingItem];
    }
    
    NSMutableArray<PKPaymentSummaryItem *> *summaryItems = summaryItemsApplePay;
    if ([summaryItems count] > 1 ) {
        summaryItems = [[NSMutableArray alloc] initWithObjects:summaryItems[0], nil];
    }
    PKShippingMethod *shippingItem = shippingMethods[0];
    
    PKPaymentSummaryItem *summaryItem = [[PKPaymentSummaryItem alloc] init];
    summaryItem.label = @"Shipping Costs";
    summaryItem.amount = shippingItem.amount;
    [summaryItems addObject:summaryItem];
    
    PKPaymentSummaryItem *summaryItemTotal = [[PKPaymentSummaryItem alloc] init];
    summaryItemTotal.label = @"Total";
    summaryItemTotal.amount = [shippingItem.amount decimalNumberByAdding:summaryItemsApplePay[0].amount];
    [summaryItems addObject:summaryItemTotal];
    
    PKPaymentRequestShippingContactUpdate *shippingContactUpdate = [[PKPaymentRequestShippingContactUpdate alloc] initWithErrors:nil paymentSummaryItems:summaryItems shippingMethods:shippingMethods];
    if (shippingContactUpdateCompletion != nil) {
        shippingContactUpdateCompletion(shippingContactUpdate);
    } else if ( shippingContactUpdateCompletionDeprecate != nil) {
        shippingContactUpdateCompletionDeprecate(PKPaymentAuthorizationStatusSuccess,shippingMethods, summaryItems);
    }
}


#pragma mark PKPaymentAuthorizationViewControllerDelegate

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                  didSelectShippingContact:(PKContact *)contact
                                completion:(void (^)(PKPaymentAuthorizationStatus status, NSArray<PKShippingMethod *> *shippingMethods,
                                                     NSArray<PKPaymentSummaryItem *> *summaryItems))completion API_DEPRECATED("Use paymentAuthorizationViewController:didSelectShippingContact:handler: instead to provide more granular errors", ios(8.0, 11.0)) {
    
    NSLog(@"paymentAuthorizationViewController");
    NSString *countryCode = contact.postalAddress.ISOCountryCode;
    NSString *countryName = contact.postalAddress.country;
    NSString *stateCode = contact.postalAddress.state;
    NSPredicate *countryCodePredicate = [NSPredicate predicateWithFormat: @" %K ==[c] %@", @"code", countryCode];
    NSPredicate *countryNamePredicate = [NSPredicate predicateWithFormat: @" %K ==[c] %@", @"name", countryName];
    NSArray *filteredCountry = [countriesApplepay filteredArrayUsingPredicate:countryCodePredicate];
    NSArray *filteredCountryByName = [countriesApplepay filteredArrayUsingPredicate:countryNamePredicate];
    if ((filteredCountry && [filteredCountry count] > 0) || (filteredCountryByName && [filteredCountryByName count] > 0 )) {
        NSString *countryCodeServer = countryCode;
        NSDictionary *country = nil;
        if (filteredCountryByName && [filteredCountryByName count] > 0) {
            countryCodeServer = [filteredCountryByName[0] valueForKey:@"code"];
            country = filteredCountryByName[0];
        } else {
            country = filteredCountry[0];
        }
        
        NSArray *states = [country valueForKey:@"states"];
        NSArray *stateByCode = [states valueForKey:stateCode];
        
        if ([states count] == 0) {
            shippingContactUpdateCompletionDeprecate = completion;
            [TPSUpdateShippingCosts fetchShippingCosts:countryCodeServer stateCode:stateCode];
            return;
        }
        
        //        NSArray * statesValues = [states allValues];
        NSPredicate *statePredicateName = [NSPredicate predicateWithFormat: @"%K ==[c] %@", @"name", stateCode];
        NSArray *filteredStateByName = [states filteredArrayUsingPredicate:statePredicateName];
        
        if ((stateByCode && [stateByCode count] > 0) || (filteredStateByName && [filteredStateByName count] > 0)) {
            NSString *stateCodeServer = stateCode;
            if (filteredStateByName && [filteredStateByName count] > 0) {
                stateCodeServer = [filteredStateByName[0] valueForKey:@"code"];
            }
            shippingContactUpdateCompletionDeprecate = completion;
            [TPSUpdateShippingCosts fetchShippingCosts:countryCodeServer stateCode:stateCodeServer];
        } else {
            completion(PKPaymentAuthorizationStatusInvalidShippingPostalAddress, nil, nil);
        }
    } else {
        completion(PKPaymentAuthorizationStatusInvalidShippingPostalAddress, nil, nil);
    }
}

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                  didSelectShippingContact:(PKContact *)contact
                                   handler:(void (^)(PKPaymentRequestShippingContactUpdate *update))completion
API_AVAILABLE(ios(11.0), watchos(4.0)) {
    NSLog(@"paymentAuthorizationViewController");
    NSString *countryCode = contact.postalAddress.ISOCountryCode;
    NSString *countryName = contact.postalAddress.country;
    NSString *stateCode = contact.postalAddress.state;
    NSPredicate *countryCodePredicate = [NSPredicate predicateWithFormat: @"%K ==[c] %@", @"code", countryCode];
    NSPredicate *countryNamePredicate = [NSPredicate predicateWithFormat: @"%K ==[c] %@", @"name", countryName];
    NSArray *filteredCountry = [countriesApplepay filteredArrayUsingPredicate:countryCodePredicate];
    NSArray *filteredCountryByName = [countriesApplepay filteredArrayUsingPredicate:countryNamePredicate];
    // Validate Shipping Adress first
    if ((filteredCountry && [filteredCountry count] > 0) || (filteredCountryByName && [filteredCountryByName count] > 0 )) {
        NSString *countryCodeServer = countryCode;
        NSDictionary *country = nil;
        if (filteredCountryByName && [filteredCountryByName count] > 0) {
            countryCodeServer = [filteredCountryByName[0] valueForKey:@"code"];
            country = filteredCountryByName[0];
        } else {
            country = filteredCountry[0];
        }
        
        NSArray *states = [country valueForKey:@"states"];
        NSArray *stateByCode = [states valueForKey:stateCode];
        
        if ([states count] == 0) {
            shippingContactUpdateCompletion = completion;
            [TPSUpdateShippingCosts fetchShippingCosts:countryCodeServer stateCode:stateCode];
            return;
        }
        
        //        NSArray * statesValues = [states allValues];
        NSPredicate *statePredicateName = [NSPredicate predicateWithFormat: @"%K ==[c] %@", @"name", stateCode];
        NSArray *filteredStateByName = [states filteredArrayUsingPredicate:statePredicateName];
        
        if ((stateByCode && [stateByCode count] > 0) || (filteredStateByName && [filteredStateByName count] > 0)) {
            NSString *stateCodeServer = stateCode;
            if (filteredStateByName && [filteredStateByName count] > 0) {
                stateCodeServer = [filteredStateByName[0] valueForKey:@"code"];
            }
            shippingContactUpdateCompletion = completion;
            [TPSUpdateShippingCosts fetchShippingCosts:countryCodeServer stateCode:stateCodeServer];
        } else {
            NSError *stateCodeError = [[NSError alloc] initWithDomain:PKPaymentErrorDomain
                                                                 code:PKPaymentShippingContactInvalidError
                                                             userInfo:@{NSLocalizedDescriptionKey: @"State is invalid",
                                                                        PKPaymentErrorContactFieldUserInfoKey: PKContactFieldPostalAddress,
                                                                        PKPaymentErrorPostalAddressUserInfoKey:CNPostalAddressStateKey}];
            PKPaymentRequestShippingContactUpdate *shippingContactUpdate = [[PKPaymentRequestShippingContactUpdate alloc] initWithErrors:@[stateCodeError] paymentSummaryItems:nil shippingMethods:nil];
            return completion(shippingContactUpdate);
        }
    } else {
        NSError *stateCodeError = [[NSError alloc] initWithDomain:PKPaymentErrorDomain
                                                             code:PKPaymentShippingContactInvalidError
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Country is invalid",
                                                                    PKPaymentErrorContactFieldUserInfoKey: PKContactFieldPostalAddress,
                                                                    PKPaymentErrorPostalAddressUserInfoKey:CNPostalAddressCountryKey}];
        PKPaymentRequestShippingContactUpdate *shippingContactUpdate = [[PKPaymentRequestShippingContactUpdate alloc] initWithErrors:@[stateCodeError] paymentSummaryItems:nil shippingMethods:nil];
        return completion(shippingContactUpdate);
    }
    
}

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                   didSelectShippingMethod:(PKShippingMethod *)shippingMethod
                                completion:(void (^)(PKPaymentAuthorizationStatus status, NSArray<PKPaymentSummaryItem *> *summaryItems))completion API_DEPRECATED("Use paymentAuthorizationViewController:didSelectShippingMethod:handler: instead to provide more granular errors", ios(8.0, 11.0)) {
    NSMutableArray<PKPaymentSummaryItem *> *summaryItems = summaryItemsApplePay;
    if ([summaryItems count] > 1 ) {
        summaryItems = [[NSMutableArray alloc] initWithObjects:summaryItems[0], nil];
    }
    
    PKPaymentSummaryItem *summaryItem = [[PKPaymentSummaryItem alloc] init];
    summaryItem.label = @"Shipping Costs";
    summaryItem.amount = shippingMethod.amount;
    [summaryItems addObject:summaryItem];
    
    PKPaymentSummaryItem *summaryItemTotal = [[PKPaymentSummaryItem alloc] init];
    summaryItemTotal.label = @"Total";
    summaryItemTotal.amount = [shippingMethod.amount decimalNumberByAdding:summaryItems[0].amount];
    [summaryItems addObject:summaryItemTotal];
    
    completion(PKPaymentAuthorizationStatusSuccess, summaryItems);
    
}

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                   didSelectShippingMethod:(PKShippingMethod *)shippingMethod
                                   handler:(void (^)(PKPaymentRequestShippingMethodUpdate *update))completion API_AVAILABLE(ios(11.0), watchos(4.0)) {
    NSMutableArray<PKPaymentSummaryItem *> *summaryItems = summaryItemsApplePay;
    if ([summaryItems count] > 1 ) {
        summaryItems = [[NSMutableArray alloc] initWithObjects:summaryItems[0], nil];
    }
    
    PKPaymentSummaryItem *summaryItem = [[PKPaymentSummaryItem alloc] init];
    summaryItem.label = @"Shipping Costs";
    summaryItem.amount = shippingMethod.amount;
    [summaryItems addObject:summaryItem];
    
    PKPaymentSummaryItem *summaryItemTotal = [[PKPaymentSummaryItem alloc] init];
    summaryItemTotal.label = @"Total";
    summaryItemTotal.amount = [shippingMethod.amount decimalNumberByAdding:summaryItems[0].amount];
    [summaryItems addObject:summaryItemTotal];
    
    PKPaymentRequestShippingMethodUpdate *shippingContactUpdate = [[PKPaymentRequestShippingMethodUpdate alloc] initWithPaymentSummaryItems:summaryItems];
    
    completion(shippingContactUpdate);
    
}


//


- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                       didAuthorizePayment:(PKPayment *)payment
                                completion:(void (^)(PKPaymentAuthorizationStatus))completion {
    // Save for deffered call
    applePayCompletion = completion;
    
    [[STPAPIClient sharedClient] createTokenWithPayment:payment completion:^(STPToken * _Nullable token, NSError * _Nullable error) {
        requestIsCompleted = YES;
        
        if (error) {
            completion(PKPaymentAuthorizationStatusFailure);
            promiseRejector(nil, nil, error);
        } else {
            NSDictionary *result = [self convertTokenObject:token];
            NSDictionary *extra = @{
                                    @"billingContact": [self contactDetails:payment.billingContact] ?: [NSNull null],
                                    @"shippingContact": [self contactDetails:payment.shippingContact] ?: [NSNull null],
                                    @"shippingMethod": [self shippingDetails:payment.shippingMethod] ?: [NSNull null]
                                    };
            
            [result setValue:extra forKey:@"extra"];
            
            promiseResolver(result);
        }
    }];
}


- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
    [RCTPresentedViewController() dismissViewControllerAnimated:YES completion:nil];
    
    if (!requestIsCompleted) {
        requestIsCompleted = YES;
        
        NSError *error = [TPSError userCancelError];
        promiseRejector([NSString stringWithFormat:@"%ld", error.code], error.localizedDescription, error);
    } else {
        promiseResolver(nil);
    }
}

- (NSDictionary *)convertTokenObject:(STPToken*)token {
    NSMutableDictionary *result = [@{} mutableCopy];
    
    // Token
    [result setValue:token.tokenId forKey:@"tokenId"];
    [result setValue:@([token.created timeIntervalSince1970]) forKey:@"created"];
    [result setValue:@(token.livemode) forKey:@"livemode"];
    
    // Card
    if (token.card) {
        NSMutableDictionary *card = [@{} mutableCopy];
        [result setValue:card forKey:@"card"];
        
        [card setValue:token.card.cardId forKey:@"cardId"];
        
        [card setValue:[self cardBrand:token.card.brand] forKey:@"brand"];
        [card setValue:[self cardFunding:token.card.funding] forKey:@"funding"];
        [card setValue:token.card.last4 forKey:@"last4"];
        [card setValue:token.card.dynamicLast4 forKey:@"dynamicLast4"];
        [card setValue:@(token.card.isApplePayCard) forKey:@"isApplePayCard"];
        [card setValue:@(token.card.expMonth) forKey:@"expMonth"];
        [card setValue:@(token.card.expYear) forKey:@"expYear"];
        [card setValue:token.card.country forKey:@"country"];
        [card setValue:token.card.currency forKey:@"currency"];
        
        [card setValue:token.card.name forKey:@"name"];
        [card setValue:token.card.addressLine1 forKey:@"addressLine1"];
        [card setValue:token.card.addressLine2 forKey:@"addressLine2"];
        [card setValue:token.card.addressCity forKey:@"addressCity"];
        [card setValue:token.card.addressState forKey:@"addressState"];
        [card setValue:token.card.addressCountry forKey:@"addressCountry"];
        [card setValue:token.card.addressZip forKey:@"addressZip"];
    }
    
    // Bank Account
    if (token.bankAccount) {
        NSMutableDictionary *bankAccount = [@{} mutableCopy];
        [result setValue:bankAccount forKey:@"bankAccount"];
        
        NSString *bankAccountStatusString =
        [RCTConvert STPBankAccountStatusString:token.bankAccount.status];
        [bankAccount setValue:bankAccountStatusString forKey:@"status"];
        [bankAccount setValue:token.bankAccount.country forKey:@"countryCode"];
        [bankAccount setValue:token.bankAccount.currency forKey:@"currency"];
        [bankAccount setValue:token.bankAccount.bankAccountId forKey:@"bankAccountId"];
        [bankAccount setValue:token.bankAccount.bankName forKey:@"bankName"];
        [bankAccount setValue:token.bankAccount.last4 forKey:@"last4"];
        [bankAccount setValue:token.bankAccount.accountHolderName forKey:@"accountHolderName"];
        NSString *bankAccountHolderTypeString =
        [RCTConvert STPBankAccountHolderTypeString:token.bankAccount.accountHolderType];
        [bankAccount setValue:bankAccountHolderTypeString forKey:@"accountHolderType"];
    }
    
    return result;
}

- (NSString *)cardBrand:(STPCardBrand)inputBrand {
    switch (inputBrand) {
        case STPCardBrandJCB:
            return @"JCB";
        case STPCardBrandAmex:
            return @"American Express";
        case STPCardBrandVisa:
            return @"Visa";
        case STPCardBrandDiscover:
            return @"Discover";
        case STPCardBrandDinersClub:
            return @"Diners Club";
        case STPCardBrandMasterCard:
            return @"MasterCard";
        case STPCardBrandUnknown:
        default:
            return @"Unknown";
    }
}

- (NSString *)cardFunding:(STPCardFundingType)inputFunding {
    switch (inputFunding) {
        case STPCardFundingTypeDebit:
            return @"debit";
        case STPCardFundingTypeCredit:
            return @"credit";
        case STPCardFundingTypePrepaid:
            return @"prepaid";
        case STPCardFundingTypeOther:
        default:
            return @"unknown";
    }
}

- (NSDictionary *)contactDetails:(PKContact*)inputContact {
    NSMutableDictionary *contactDetails = [[NSMutableDictionary alloc] init];
    
    if (inputContact.name) {
        [contactDetails setValue:[NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:inputContact.name style:NSPersonNameComponentsFormatterStyleDefault options:0] forKey:@"name"];
    }
    
    if (inputContact.phoneNumber) {
        [contactDetails setValue:[inputContact.phoneNumber stringValue] forKey:@"phoneNumber"];
    }
    
    if (inputContact.emailAddress) {
        [contactDetails setValue:inputContact.emailAddress forKey:@"emailAddress"];
    }
    
    if (inputContact.supplementarySubLocality) {
        [contactDetails setValue:inputContact.supplementarySubLocality forKey:@"supplementarySubLocality"];
    }
    
    for (NSString *elem in @[@"street", @"city", @"state", @"country", @"ISOCountryCode", @"postalCode"]) {
        if ([inputContact.postalAddress respondsToSelector:NSSelectorFromString(elem)]) {
            [contactDetails setValue:[inputContact.postalAddress valueForKey:elem] forKey:elem];
        }
    }
    if ([contactDetails count] == 0) {
        return nil;
    }
    
    return contactDetails;
}

- (NSDictionary *)shippingDetails:(PKShippingMethod*)inputShipping {
    NSMutableDictionary *shippingDetails = [[NSMutableDictionary alloc] init];
    
    if (inputShipping.label) {
        [shippingDetails setValue:inputShipping.label forKey:@"label"];
    }
    
    if (inputShipping.amount) {
        [shippingDetails setValue:[[self numberFormatter] stringFromNumber: inputShipping.amount] forKey:@"amount"];
    }
    
    if (inputShipping.detail) {
        [shippingDetails setValue:inputShipping.detail forKey:@"detail"];
    }
    
    if (inputShipping.identifier) {
        [shippingDetails setValue:inputShipping.identifier forKey:@"id"];
    }
    
    if ([shippingDetails count] == 0) {
        return nil;
    }
    
    return shippingDetails;
}

- (PKAddressField)applePayAddressFields:(NSArray <NSString *> *)addressFieldStrings {
    PKAddressField addressField = PKAddressFieldNone;
    
    for (NSString *addressFieldString in addressFieldStrings) {
        addressField |= [self applePayAddressField:addressFieldString];
    }
    
    return addressField;
}

- (PKAddressField)applePayAddressField:(NSString *)addressFieldString {
    PKAddressField addressField = PKAddressFieldNone;
    if ([addressFieldString isEqualToString:@"postal_address"]) {
        addressField = PKAddressFieldPostalAddress;
    }
    if ([addressFieldString isEqualToString:@"phone"]) {
        addressField = PKAddressFieldPhone;
    }
    if ([addressFieldString isEqualToString:@"email"]) {
        addressField = PKAddressFieldEmail;
    }
    if ([addressFieldString isEqualToString:@"name"]) {
        addressField = PKAddressFieldName;
    }
    if ([addressFieldString isEqualToString:@"all"]) {
        addressField = PKAddressFieldAll;
    }
    return addressField;
}

- (PKShippingType)applePayShippingType:(NSString*)inputType {
    PKShippingType shippingType = PKShippingTypeShipping;
    if ([inputType isEqualToString:@"delivery"]) {
        shippingType = PKShippingTypeDelivery;
    }
    if ([inputType isEqualToString:@"store_pickup"]) {
        shippingType = PKShippingTypeStorePickup;
    }
    if ([inputType isEqualToString:@"service_pickup"]) {
        shippingType = PKShippingTypeServicePickup;
    }
    
    return shippingType;
}

- (STPBillingAddressFields)billingType:(NSString*)inputType {
    if ([inputType isEqualToString:@"zip"]) {
        return STPBillingAddressFieldsZip;
    }
    if ([inputType isEqualToString:@"full"]) {
        return STPBillingAddressFieldsFull;
    }
    return STPBillingAddressFieldsNone;
}

- (STPUserInformation *)userInformation:(NSDictionary*)inputInformation {
    STPUserInformation *userInformation = [[STPUserInformation alloc] init];
    
    [userInformation setEmail:inputInformation[@"email"]];
    [userInformation setPhone:inputInformation[@"phone"]];
    [userInformation setBillingAddress: [self address:inputInformation[@"billingAddress"]]];
    
    return userInformation;
}

- (STPAddress *)address:(NSDictionary*)inputAddress {
    STPAddress *address = [[STPAddress alloc] init];
    
    [address setName:inputAddress[@"name"]];
    [address setLine1:inputAddress[@"line1"]];
    [address setLine2:inputAddress[@"line2"]];
    [address setCity:inputAddress[@"city"]];
    [address setState:inputAddress[@"state"]];
    [address setPostalCode:inputAddress[@"postalCode"]];
    [address setCountry:inputAddress[@"country"]];
    [address setPhone:inputAddress[@"phone"]];
    [address setEmail:inputAddress[@"email"]];
    
    return address;
}

- (STPTheme *)formTheme:(NSDictionary*)options {
    STPTheme *theme = [[STPTheme alloc] init];
    
    [theme setPrimaryBackgroundColor:[RCTConvert UIColor:options[@"primaryBackgroundColor"]]];
    [theme setSecondaryBackgroundColor:[RCTConvert UIColor:options[@"secondaryBackgroundColor"]]];
    [theme setPrimaryForegroundColor:[RCTConvert UIColor:options[@"primaryForegroundColor"]]];
    [theme setSecondaryForegroundColor:[RCTConvert UIColor:options[@"secondaryForegroundColor"]]];
    [theme setAccentColor:[RCTConvert UIColor:options[@"accentColor"]]];
    [theme setErrorColor:[RCTConvert UIColor:options[@"errorColor"]]];
    [theme setErrorColor:[RCTConvert UIColor:options[@"errorColor"]]];
    // TODO: process font vars
    
    return theme;
}

- (UIModalPresentationStyle)formPresentation:(NSString*)inputType {
    if ([inputType isEqualToString:@"pageSheet"])
        return UIModalPresentationPageSheet;
    if ([inputType isEqualToString:@"formSheet"])
        return UIModalPresentationFormSheet;
    
    return UIModalPresentationFullScreen;
}

+ (NSArray <NSString *> *)supportedPaymentNetworksStrings {
    return @[
             TPSPaymentNetworkAmex,
             TPSPaymentNetworkDiscover,
             TPSPaymentNetworkMasterCard,
             TPSPaymentNetworkVisa,
             ];
}

- (NSArray <PKPaymentNetwork> *)paymentNetworks:(NSArray <NSString *> *)paymentNetworkStrings {
    NSMutableArray <PKPaymentNetwork> *results = [@[] mutableCopy];
    
    for (NSString *paymentNetworkString in paymentNetworkStrings) {
        PKPaymentNetwork paymentNetwork = [self paymentNetwork:paymentNetworkString];
        if (paymentNetwork) {
            [results addObject:paymentNetwork];
        }
    }
    
    return [results copy];
}

- (PKPaymentNetwork)paymentNetwork:(NSString *)paymentNetworkString {
    static NSDictionary *paymentNetworksMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *mutableMap = [@{} mutableCopy];
        
        if ((&PKPaymentNetworkAmex) != NULL) {
            mutableMap[TPSPaymentNetworkAmex] = PKPaymentNetworkAmex;
        }
        
        if ((&PKPaymentNetworkDiscover) != NULL) {
            mutableMap[TPSPaymentNetworkDiscover] = PKPaymentNetworkDiscover;
        }
        
        if ((&PKPaymentNetworkMasterCard) != NULL) {
            mutableMap[TPSPaymentNetworkMasterCard] = PKPaymentNetworkMasterCard;
        }
        
        if ((&PKPaymentNetworkVisa) != NULL) {
            mutableMap[TPSPaymentNetworkVisa] = PKPaymentNetworkVisa;
        }
        
        paymentNetworksMap = [mutableMap copy];
    });
    
    return paymentNetworksMap[paymentNetworkString];
}

- (NSNumberFormatter *)numberFormatter {
    static NSNumberFormatter *kSharedFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kSharedFormatter = [[NSNumberFormatter alloc] init];
        [kSharedFormatter setPositiveFormat:@"$0.00"];
    });
    return kSharedFormatter;
}

@end
