//
//  AppDelegate.m
//  QuickRadar
//
//  Created by Amy Worrall on 15/05/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"
#import "PTHotKeyLib.h"
#import "QRRadarWindowController.h"
#import <Growl/Growl.h>
#import "QRPreferencesWindowController.h"
#import "QRUserDefaultsKeys.h"
#import "QRAppListManager.h"

@interface AppDelegate () <GrowlApplicationBridgeDelegate>
{
	NSMutableSet *windowControllerStore;
    NSStatusItem *statusItem;
}

@property (strong) QRPreferencesWindowController *preferencesWindowController;
@property (assign, nonatomic) BOOL applicationHasStarted;

@end


@implementation AppDelegate

@synthesize menu = _menu;
@synthesize preferencesWindowController = _preferencesWindowController;
@synthesize applicationHasStarted = _applicationHasStarted;

#pragma mark NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    //setup statusItem
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    statusItem.image = [NSImage imageNamed:@"MenubarTemplate"];
	statusItem.highlightMode = YES;
    statusItem.menu = self.menu;

    //apply hotkey
    [self applyHotkey];
    
    //observe defaults for hotkey
    [[NSUserDefaultsController sharedUserDefaultsController]
     addObserver:self forKeyPath:GlobalHotkeyKeyPath options:0 context: NULL];
    
	windowControllerStore = [NSMutableSet set];
	
	[GrowlApplicationBridge setGrowlDelegate:self];
	
	self.preferencesWindowController = [[QRPreferencesWindowController alloc] initWithWindowNibName:@"QRPreferencesWindowController"];

	BOOL shouldShowDockIcon = [[NSUserDefaults standardUserDefaults] boolForKey:QRShowInDockKey];
	
	if (shouldShowDockIcon)
	{
		ProcessSerialNumber psn = {0, kCurrentProcess};
		verify_noerr(TransformProcessType(&psn, 
										  kProcessTransformToForegroundApplication));
	}
	
	// Start tracking apps.
	[QRAppListManager sharedManager];
	
	self.applicationHasStarted = YES;

	NSAppleEventManager *em = [NSAppleEventManager sharedAppleEventManager];
	[em
	 setEventHandler:self
	 andSelector:@selector(getUrl:withReplyEvent:)
	 forEventClass:kInternetEventClass
	 andEventID:kAEGetURL];
	
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
	LSSetDefaultHandlerForURLScheme((CFStringRef)@"rdar", (__bridge CFStringRef)bundleID);
	LSSetDefaultHandlerForURLScheme((CFStringRef)@"quickradar", (__bridge CFStringRef)bundleID);
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender;
{
	return (self.applicationHasStarted);
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication;
{
	[self newBug:self];
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	[[QRAppListManager sharedManager] saveList];
}

#pragma mark - Prefs

- (IBAction)showPreferencesWindow:(id)sender;
{
	NSLog(@"Pref");
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	[self.preferencesWindowController showWindow:self];
}

#pragma mark growl support

- (NSDictionary *) registrationDictionaryForGrowl;
{
	NSArray *notifications = [NSArray arrayWithObjects:@"Submission Complete", @"Submission Failed", nil];
	
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:notifications, GROWL_NOTIFICATIONS_ALL, notifications, GROWL_NOTIFICATIONS_DEFAULT, nil];
	return dict;
}

- (NSString *) applicationNameForGrowl;
{
	return @"QuickRadar";
}

- (void) growlNotificationWasClicked:(id)clickContext;
{
	NSDictionary *dict = (NSDictionary*)clickContext;
	
	NSLog(@"Context %@", dict);
	
	NSString *stringURL = [dict objectForKey:@"URL"];
	
	if (!stringURL)
		return;
	
	NSURL *url = [NSURL URLWithString:stringURL];
	[[NSWorkspace sharedWorkspace] openURL:url];
}


#pragma mark IBActions

- (IBAction)activateAndShowAbout:(id)sender;
{
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	[NSApp orderFrontStandardAboutPanel:self];
}



- (IBAction)newBug:(id)sender;
{
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	
    QRRadarWindowController *b = [[QRRadarWindowController alloc] initWithWindowNibName:@"RadarWindow"];
    [windowControllerStore addObject:b];
    [b showWindow:nil];
	
}


- (IBAction)bugWindowControllerSubmissionComplete:(id)sender
{
	[windowControllerStore removeObject:sender];
}


#pragma mark keyComboPanelDelegate

- (void)keyComboPanelEnded:(PTKeyComboPanel*)panel {
	[[NSUserDefaults standardUserDefaults] setObject:[[panel keyCombo] plistRepresentation] forKey:GlobalHotkeyName];
}

#pragma mark hotkey

- (void)applyHotkey {
	//unregister old
	for (PTHotKey *hotkey in [[PTHotKeyCenter sharedCenter] allHotKeys]) {
		[[PTHotKeyCenter sharedCenter] unregisterHotKey:hotkey];
	}
    
	//read plist
	id plistTool = [[NSUserDefaults standardUserDefaults] objectForKey:GlobalHotkeyName];
    
    //make default
	if(!plistTool) {
        plistTool = [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSNumber numberWithInt:49], @"keyCode",
                     [NSNumber numberWithInt:cmdKey+controlKey+optionKey], @"modifiers",
                     nil];
        
        [[NSUserDefaults standardUserDefaults] setObject:plistTool forKey:GlobalHotkeyName];
	}
    
    //get key combo
    PTKeyCombo *kc = [[PTKeyCombo alloc] initWithPlistRepresentation:plistTool];
    
    //register it
    PTHotKey *hotKey = [[PTHotKey alloc] init];
    hotKey.name = GlobalHotkeyName;
    hotKey.keyCombo = kc;
    hotKey.target = self;
    hotKey.action = @selector(hitHotKey:);
    [[PTHotKeyCenter sharedCenter] registerHotKey:hotKey];
    
    //update menu to show it (HACKISH)
    [_menu itemWithTag:10].title = [NSString stringWithFormat:@"Post new Bug... (%@)", kc];
}

- (void)hitHotKey:(id)sender {
    [self newBug:sender];
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:object
						change:(NSDictionary *)change context:(void *)context {
	if([keyPath isEqualToString:GlobalHotkeyKeyPath]) {
		[self applyHotkey];
	}
}

#pragma mark URL handling
- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	// Get the URL
	NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject]
						stringValue];
	NSURL *url = [NSURL URLWithString:urlStr];
	
	if ([url.scheme isEqualToString:@"rdar"])
	{
		NSString *rdarId = url.host;
		if ([rdarId isEqualToString:@"problem"]) {
			rdarId = url.lastPathComponent;
		}
		
		NSURL *openRadarURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://openradar.appspot.com/%@", rdarId]];
		[[NSWorkspace sharedWorkspace] openURL:openRadarURL];

	}
	else if ([url.scheme isEqualToString:@"quickradar"])
	{
		// TODO: some way of having the service class register a block for its URL handler. This is a quick-and-dirty method in the mean time.
		
		NSString *urlStr = [url.absoluteString stringByReplacingOccurrencesOfString:@"quickradar://" withString:@""];
		
		if ([urlStr hasPrefix:@"appdotnetauth"])
		{
			NSArray *parts = [url.absoluteString componentsSeparatedByString:@"#"];
			NSString *token = parts[1];
			
			if ([token hasPrefix:@"access_token="])
			{
				token = [token stringByReplacingOccurrencesOfString:@"access_token=" withString:@""];
				[[NSUserDefaults standardUserDefaults] setObject:token forKey:@"appDotNetUserToken"];
			}
			else
			{
				[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"appDotNetUserToken"];
			}
			
		}
	}
	
}


@end
