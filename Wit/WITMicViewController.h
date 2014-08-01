//
//  WITMicViewController.h
//  WitAnimations
//
//  Created by Erik Villegas on 6/27/14.
//  Copyright (c) 2014 Wit.AI. All rights reserved.
//

#import <UIKit/UIKit.h>

@class WITResponse;
@protocol WITMicViewControllerDelegate;

typedef NS_ENUM(NSInteger, WITMicState) {
    
    WITMicStateStandby,
    WITMicStateListening,
    WITMicStateProcessing,
    WITMicStateDisabled
};

@interface WITMicViewController : UIViewController

@property (nonatomic, assign) WITMicState state;
@property (nonatomic, weak) id<WITMicViewControllerDelegate> delegate;

@end

@protocol WITMicViewControllerDelegate <NSObject>

// Invoked when Wit.AI returns a successful response.
- (void) micViewController:(WITMicViewController *) controller didReceiveResponse:(WITResponse *) response;

// Invoked when Wit.AI returns an error.
- (void) micViewController:(WITMicViewController *) controller didFailWithError:(NSError *) error;

// Invoked when this class cancelled a request (due to no speech detected)
- (void) micViewControllerDidCancelRequest:(WITMicViewController *) controller;

@end