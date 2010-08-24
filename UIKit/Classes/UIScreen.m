//  Created by Sean Heber on 5/27/10.
#import "UIScreen.h"
#import "UIImage+UIPrivate.h"
#import "UIImageView.h"
#import "UIApplication.h"
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>
#import "UIViewLayoutManager.h"
#import "UIColor.h"
#import "UIScreenMode+UIPrivate.h"

NSString *const UIScreenDidConnectNotification = @"UIScreenDidConnectNotification";
NSString *const UIScreenDidDisconnectNotification = @"UIScreenDidDisconnectNotification";
NSString *const UIScreenModeDidChangeNotification = @"UIScreenModeDidChangeNotification";

static NSMutableArray *_allScreens = nil;

@implementation UIScreen
@synthesize currentMode=_currentMode;

+ (void)initialize
{
	if (self == [UIScreen class]) {
		_allScreens = [NSMutableArray new];
	}
}

+ (UIScreen *)mainScreen
{
	return ([_allScreens count] > 0)? [[_allScreens objectAtIndex:0] nonretainedObjectValue] : nil;
}

+ (NSArray *)screens
{
	NSMutableArray *screens = [NSMutableArray arrayWithCapacity:[_allScreens count]];

	for (NSValue *v in _allScreens) {
		[screens addObject:[v nonretainedObjectValue]];
	}

	return screens;
}

- (id)init
{
    if ((self = [super init])) {
		_layer = [[CALayer layer] retain];
		_layer.delegate = self;		// required to get the magic of the UIViewLayoutManager...
		_layer.layoutManager = [UIViewLayoutManager layoutManager];

		// NOTE: This line adds a 10.6 depedency The commented out line after this would appear to do a similar thing and should work on 10.5,
		// but ironically, it then makes the UIImageView images render upside down. I suspect this has to do with flipped-ness of images, but
		// in trying to track that down I noticed that I'm using at least one 10.6-only NSImage method in there already, so I decided it wasn't
		// worth the effort right now to bother with 10.5 support since there'd be a couple changes there and who knows what other things are
		// lurking around that only works on 10.6. Got bigger fish to fry right now.
		_layer.geometryFlipped = YES;
		//_layer.sublayerTransform = CATransform3DMakeScale(1,-1,1);
		
		_grabber = [[UIImageView alloc] initWithImage:[UIImage _frameworkImageNamed:@"<UIScreen> grabber.png"]];
		_grabber.layer.zPosition = 10000;
		[_layer addSublayer:_grabber.layer];
    }
    return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_allScreens removeObject:[NSValue valueWithNonretainedObject:self]];
	[_grabber release];
	[_layer release];
	[super dealloc];
}

- (void)_setPopoverController:(UIPopoverController *)controller
{
	_popoverController = controller;
}

- (UIPopoverController *)_popoverController
{
	return _popoverController;
}

- (BOOL)_hasResizeIndicator
{
	NSWindow *realWindow = [_NSView window];

	if (realWindow && ([realWindow styleMask] & NSResizableWindowMask) && [realWindow showsResizeIndicator] ) {
		NSView *contentView = [realWindow contentView];
		
		const CGRect myBounds = NSRectToCGRect([_NSView bounds]);
		const CGPoint myLowerRight = CGPointMake(CGRectGetMaxX(myBounds),CGRectGetMaxY(myBounds));
		const CGRect contentViewBounds = NSRectToCGRect([contentView frame]);
		const CGPoint contentViewLowerRight = CGPointMake(CGRectGetMaxX(contentViewBounds),0);
		const CGPoint convertedPoint = NSPointToCGPoint([_NSView convertPoint:NSPointFromCGPoint(myLowerRight) toView:contentView]);

		if (CGPointEqualToPoint(convertedPoint,contentViewLowerRight) && [realWindow showsResizeIndicator]) {
			return YES;
		}
	}

	return NO;
}

- (void)layoutSubviews
{
	if ([self _hasResizeIndicator]) {
		const CGSize grabberSize = _grabber.frame.size;
		const CGSize layerSize = _layer.bounds.size;
		CGRect grabberRect = _grabber.frame;
		grabberRect.origin = CGPointMake(layerSize.width-grabberSize.width,layerSize.height-grabberSize.height);
		_grabber.frame = grabberRect;
		_grabber.hidden = NO;
	} else if (!_grabber.hidden) {
		_grabber.hidden = YES;
	}
}

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
	return [NSNull null];
}

- (CGRect)applicationFrame
{
	const float statusBarHeight = [UIApplication sharedApplication].statusBarHidden? 0 : 20;
	const CGSize size = [self bounds].size;
	return CGRectMake(0,statusBarHeight,size.width,size.height-statusBarHeight);
}

- (CGRect)bounds
{
	return _layer.bounds;
}

- (NSView *)_NSView
{
	return _NSView;
}

- (CALayer *)_layer
{
	return _layer;
}

- (void)_setNSView:(id)theView
{
	if (_NSView != theView) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:_NSView];
		if ((_NSView = theView)) {
			[_allScreens addObject:[NSValue valueWithNonretainedObject:self]];
			self.currentMode = [UIScreenMode screenModeWithNSView:_NSView];
			[[NSNotificationCenter defaultCenter] postNotificationName:UIScreenDidConnectNotification object:self];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_NSViewFrameDidChange:) name:NSViewFrameDidChangeNotification object:_NSView];
		} else {
			[_allScreens removeObject:[NSValue valueWithNonretainedObject:self]];
			[[NSNotificationCenter defaultCenter] postNotificationName:UIScreenDidDisconnectNotification object:self];
		}
	}
}

- (void)_NSViewFrameDidChange:(NSNotification *)note
{
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self.currentMode forKey:@"_previousMode"];
	self.currentMode = [UIScreenMode screenModeWithNSView:_NSView];
	[[NSNotificationCenter defaultCenter] postNotificationName:UIScreenModeDidChangeNotification object:self userInfo:userInfo];
}

- (NSArray *)availableModes
{
	return [NSArray arrayWithObject:self.currentMode];
}

@end


@implementation UIScreen (Extentions)
- (CGPoint)convertPoint:(CGPoint)toConvert toScreen:(UIScreen *)toScreen
{
	if (toScreen == self) {
		return toConvert;
	} else {
		// Go all the way through OSX screen coordinates.
		NSPoint screenCoords = [[_NSView window] convertBaseToScreen:[_NSView convertPoint:NSPointFromCGPoint(toConvert) toView:nil]];
		
		if (toScreen) {
			// Now from there back to the toScreen's window's base
			return NSPointToCGPoint([[toScreen _NSView] convertPoint:[[[toScreen _NSView] window] convertScreenToBase:screenCoords] fromView:nil]);
		} else {
			return NSPointToCGPoint(screenCoords);
		}
	}
}

- (CGPoint)convertPoint:(CGPoint)toConvert fromScreen:(UIScreen *)fromScreen
{
	if (fromScreen == self) {
		return toConvert;
	} else {
		NSPoint screenCoords;
		
		if (fromScreen) {
			// Go all the way through OSX screen coordinates.
			screenCoords = [[[fromScreen _NSView] window] convertBaseToScreen:[[fromScreen _NSView] convertPoint:NSPointFromCGPoint(toConvert) toView:nil]];
		} else {
			screenCoords = NSPointFromCGPoint(toConvert);
		}
		
		// Now from there back to the our screen
		return NSPointToCGPoint([_NSView convertPoint:[[_NSView window] convertScreenToBase:screenCoords] fromView:nil]);
	}
}

- (CGRect)convertRect:(CGRect)toConvert toScreen:(UIScreen *)toScreen
{
	CGPoint origin = [self convertPoint:CGPointMake(CGRectGetMinX(toConvert),CGRectGetMinY(toConvert)) toScreen:toScreen];
	CGPoint bottom = [self convertPoint:CGPointMake(CGRectGetMaxX(toConvert),CGRectGetMaxY(toConvert)) toScreen:toScreen];
	return CGRectMake(origin.x, origin.y, bottom.x-origin.x, bottom.y-origin.y);
}

- (CGRect)convertRect:(CGRect)toConvert fromScreen:(UIScreen *)fromScreen
{
	CGPoint origin = [self convertPoint:CGPointMake(CGRectGetMinX(toConvert),CGRectGetMinY(toConvert)) fromScreen:fromScreen];
	CGPoint bottom = [self convertPoint:CGPointMake(CGRectGetMaxX(toConvert),CGRectGetMaxY(toConvert)) fromScreen:fromScreen];
	return CGRectMake(origin.x, origin.y, bottom.x-origin.x, bottom.y-origin.y);
}

- (void)becomeMainScreen
{
	NSValue *entry = [NSValue valueWithNonretainedObject:self];
	NSInteger index = [_allScreens indexOfObject:entry];
	[_allScreens removeObjectAtIndex:index];
	[_allScreens insertObject:entry atIndex:0];
}

@end

