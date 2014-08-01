//
//  WITMicViewController.m
//  WitAnimations
//
//  Created by Erik Villegas on 6/27/14.
//  Copyright (c) 2014 Wit.AI. All rights reserved.
//

#import "WITMicViewController.h"
#import "SCSiriWaveformView.h"
#import "Wit.h"
#import "WitState.h"
#import "WitPrivate.h"
#import "WITResponse.h"
#import "KSReachability.h"

@import MediaPlayer;
@import AudioToolbox;

@interface WITMicViewController () <WitDelegate>

@property (nonatomic, strong) IBOutlet SCSiriWaveformView *waveformView;
@property (weak, nonatomic) IBOutlet UIImageView *micImageView;

/// Time marker for when mic becomes activated
@property (nonatomic, assign) CFTimeInterval listenStartTime;

/// Time marker for when input passes threshold
@property (nonatomic, assign) CFTimeInterval lastSpokenTime;

@property (nonatomic, strong) NSTimer *processingAnimationTimer, *microphoneAnimationTimer;

/// The audio players for start and stop sounds
@property (nonatomic, strong) AVAudioPlayer *startSoundPlayer, *stopSoundPlayer;

/// The input threshold value that triggers mic deactivation.
/// It is set dynamically based on the input device (mic/headset)
@property (nonatomic, assign) CGFloat audioInputThreshold;

@end

@implementation WITMicViewController

- (void) viewDidLoad {
    
    [super viewDidLoad];
    
    _audioInputThreshold = [self isHeadsetPluggedIn]? 0.04f : 0.1f;
	
    self.view.layer.borderColor = [UIColor whiteColor].CGColor;
    self.view.layer.borderWidth = 4.0f;

    _waveformView.alpha = 0.0f;
    _waveformView.waveColor = [UIColor whiteColor];
    _waveformView.primaryWaveLineWidth = 4.0f;
    _waveformView.numberOfWaves = 1;
    
    [Wit sharedInstance].delegate = self;
    
    // This is the pulse animation that occurs every 5 seconds
    _microphoneAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:5.0f target:self selector:@selector(animateMicrophone:) userInfo:nil repeats:YES];
    [self animateMicrophone:_microphoneAnimationTimer];
    
    // listen for network reachability changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityChangedNotificationHandler:) name:kDefaultNetworkReachabilityChangedNotification object:nil];
    
    // listen for remote control events
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(remoteControlEventReceivedNotificationHandler:) name:WITRemoteControlEventReceivedNotification object:nil];
    
    // listen for headset plugged in/out events
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    // initialize audio players
    _startSoundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"mic-start" withExtension:@"aiff"] error:nil];
    _stopSoundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"mic-stop" withExtension:@"aiff"] error:nil];
}

- (void) viewDidAppear:(BOOL)animated {
    
    [super viewDidAppear:animated];
    
    [self enterStandby];
}

- (void) viewDidLayoutSubviews {
    
    [super viewDidLayoutSubviews];
    
    self.view.layer.cornerRadius = self.view.bounds.size.width/2.0f;
}

#pragma mark - NSNotification methods

/// This callback is invoked when headset is plugged in and out
- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    
    NSInteger routeChangeReason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];
    
    if (routeChangeReason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) { // headset unplugged
        _audioInputThreshold = 0.1f;
    }
    else if (routeChangeReason == AVAudioSessionRouteChangeReasonNewDeviceAvailable) { // headset plugged in
        _audioInputThreshold = 0.04f;
    }
}

/// This callback is invoked the headset controls are tapped (only the center button)
- (void) remoteControlEventReceivedNotificationHandler:(NSNotification *) notification {
    
    [self tapGestureRecognized:nil];
}

- (void) networkReachabilityChangedNotificationHandler:(NSNotification *) notification  {
    
    KSReachability *reachability = notification.object;
    
    if (!reachability.reachable) {
        
        self.state = WITMicStateDisabled;

        _micImageView.tintColor = [UIColor lightGrayColor];
        self.view.layer.borderColor = [UIColor lightGrayColor].CGColor;
    }
    else {
        
        if (self.state == WITMicStateDisabled) {
            self.state = WITMicStateStandby;
        }

        _micImageView.tintColor = [UIColor whiteColor];
        self.view.layer.borderColor = [UIColor whiteColor].CGColor;
    }
}

#pragma mark - KVO

/// Observes the power value of audio input
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {

    if ([keyPath isEqualToString:@"power"]) {
        float power = [change[@"new"] floatValue];
        [self handleAudioPower:power];
    }
}

#pragma mark - Helper methods

- (void) handleAudioPower:(float) power {
    
    CGFloat normalizedValue = pow(10, power/20);
    
    [_waveformView updateWithLevel:normalizedValue * 2.0f];
    
    // ignore the first 0.6 seconds when checking if voice reached the threshold (because of start sound)
    if ((CACurrentMediaTime() - _listenStartTime >= 0.6f) && normalizedValue >= _audioInputThreshold) {
        _lastSpokenTime = CACurrentMediaTime();
    }
    else {
        
        // check if it's been 1 second since the last spoken time
        if (_lastSpokenTime && CACurrentMediaTime() - _lastSpokenTime >= 1.0f) {
            
            [self stopListeningWithSound:YES];
            [self startProcessingAnimation];
        }
    }
}

- (void) enterStandby {
    
    self.state = WITMicStateStandby;
    
    _micImageView.image = [[UIImage imageNamed:@"microphone-2"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _micImageView.tintColor = [UIColor whiteColor];
    
    [UIView animateWithDuration:1.0f delay:0.0f usingSpringWithDamping:0.5f initialSpringVelocity:1.0f options:0 animations:^{
        self.view.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    [UIView animateWithDuration:0.5f animations:^{
        
        self.view.backgroundColor = [UIColor clearColor];
        _waveformView.alpha = 0.0f;
        _micImageView.alpha = 1.0f;
    }];
}

- (void) startListening {
    
    self.state = WITMicStateListening;
    
    _lastSpokenTime = 0;
    
    [_startSoundPlayer play];
    
    [[Wit sharedInstance] toggleCaptureVoiceIntent:self];

    [[WITState sharedInstance].recorder addObserver:self forKeyPath:@"power" options:NSKeyValueObservingOptionNew context:nil];
    
    [UIView animateWithDuration:1.0f delay:0.0f usingSpringWithDamping:0.5f initialSpringVelocity:1.0f options:0 animations:^{
        self.view.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
    } completion:nil];
    
    [UIView animateWithDuration:0.3f animations:^{
        _waveformView.alpha = 1.0f;
        _micImageView.alpha = 0.0f;
    }];
    
    [_waveformView updateWithLevel:0.0f];
    
    _listenStartTime = CACurrentMediaTime();
}

- (void) stopListeningWithSound:(BOOL) playSound {
    
    @try{
    
        [[WITState sharedInstance].recorder removeObserver:self forKeyPath:@"power"];
    } @catch(id e) { }
    
    [[Wit sharedInstance] toggleCaptureVoiceIntent:self];
    
    if (playSound) {
        [_stopSoundPlayer play];
    }
}

- (void) startProcessingAnimation {
    
    self.state = WITMicStateProcessing;
    
    [UIView animateWithDuration:0.3f animations:^{
        _waveformView.alpha = 0.0f;
        self.view.backgroundColor = [UIColor whiteColor];
    }];
    
    [UIView animateWithDuration:1.0f delay:0.0f usingSpringWithDamping:0.5f initialSpringVelocity:1.0f options:0 animations:^{
        self.view.transform = CGAffineTransformMakeScale(0.5f, 0.5f);
    } completion:nil];
    
    _processingAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(processingAnimationTimer:) userInfo:nil repeats:YES];
    [self processingAnimationTimer:_processingAnimationTimer];
}

- (void) stopProcessingAnimation {
    
    [_processingAnimationTimer invalidate];
}

- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

#pragma mark - UIGestureRecognizer methods

- (IBAction) tapGestureRecognized:(UIGestureRecognizer *) gestureRecognizer {
    
    switch (self.state) {
        case WITMicStateStandby: {

            [self startListening];
            break;
        }
        case WITMicStateListening: {
            
            if (_lastSpokenTime > 0) {
                [self stopListeningWithSound:YES];
                [self startProcessingAnimation];
            }
            else { // if no speech detected, go back to stanby
                
                [self stopListeningWithSound:NO];
                [self enterStandby];
                [[Wit sharedInstance] cancel];
                
                if (self.delegate && [self.delegate respondsToSelector:@selector(micViewControllerDidCancelRequest:)]) {
                    [self.delegate micViewControllerDidCancelRequest:self];
                }
            }
            break;
        }
        case WITMicStateProcessing:
            break;
        case WITMicStateDisabled:
            
            
            break;
    }
}

#pragma mark - WitDelegate methods

- (void)witDidGraspIntent:(NSString *)intent entities:(NSDictionary *)entities body:(NSString *)body error:(NSError *)error {
    
//    NSLog(@"[Wit] Entities: %@", entities);
//    NSLog(@"[Wit] Intent: %@", intent);
//    NSLog(@"[Wit] Body: %@", body);
    
    if (error) {
        
        NSLog(@"[Wit] error: %@", [error localizedDescription]);

        if (_delegate && [_delegate respondsToSelector:@selector(micViewController:didFailWithError:)]) {
            [_delegate micViewController:self didFailWithError:error];
        }
    }
    else {
    
        WITResponse *response = [[WITResponse alloc] init];
        response.entities = entities;
        response.intent = intent;
        response.body = body;
        
        if (_delegate && [_delegate respondsToSelector:@selector(micViewController:didReceiveResponse:)]) {
            [_delegate micViewController:self didReceiveResponse:response];
        }
    }
    
    [self stopProcessingAnimation];
    [self enterStandby];
}

- (void)didNotFindIntentSelectorForIntent:(NSString *)intent entities:(NSDictionary *)entities body:(NSString *)body {
    
}

#pragma mark - NSTimer methods

- (void) processingAnimationTimer:(NSTimer *) timer {
    
    static NSInteger count = 0;
    
    NSString *keyPath = (count % 2 == 0)? @"transform.rotation.y" : @"transform.rotation.x";
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
    animation.fromValue = @(0.0f);
    animation.toValue = @(M_PI);
    animation.duration = 0.25;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.view.layer addAnimation:animation forKey:@"rotateAnimation"];
    
    count++;
}

- (void) animateMicrophone:(NSTimer *) timer {
    
    if (self.state == WITMicStateStandby) {

        CABasicAnimation *theAnimation;
        
        theAnimation=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
        theAnimation.duration = 0.4f;
        theAnimation.repeatCount = 1.0f;
        theAnimation.autoreverses = YES;
        theAnimation.fromValue=[NSNumber numberWithFloat:1.0];
        theAnimation.toValue=[NSNumber numberWithFloat:1.1];
        theAnimation.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.79f :-0.47f :0.53f :0.99f];
        [self.view.layer addAnimation:theAnimation forKey:@"animateOpacity"]; //myButton.layer instead of
    }
}

@end