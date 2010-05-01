//
//  TreeMapView.h
//  TreeMapView
//
//  Created by Tjark Derlien on Mon Sep 29 2003.
//  Copyright 2003 Tjark Derlien. All rights reserved.
//

#import "TreeMapView.h"
#import "NSBitmapImageRep-CreationExtensions.h"
#import "ZoomInfo.h"

NSString *TreeMapViewItemTouchedNotification = @"TreeMapViewItemTouched";
NSString *TreeMapViewSelectionDidChangedNotification = @"TreeMapViewSelectionDidChangeed";
NSString *TreeMapViewSelectionIsChangingNotification = @"TreeMapViewSelectionIsChanging";
NSString *TMVTouchedItem = @"TreeMapViewTouchedItem"; //key for touched item in userInfo of a TreeMapViewItemTouchedNotification

//================ interface TreeMapView(Private) ======================================================

@interface TreeMapView(Private)

- (void) drawInCache;
- (void) allocContentCache;
- (void) deallocContentCache;
- (TMVItem*) findTMVItemByPathToDataItem: (NSArray*) path;
- (void) performZoom: (ZoomInfo*) zoomInfo;

@end

//================ implementation TreeMapView ======================================================

@implementation TreeMapView

- (id)initWithFrame:(NSRect)frameRect
{
    [super initWithFrame:frameRect];
	
    if ([[self superclass] instancesRespondToSelector:@selector(awakeFromNib)])
        [super awakeFromNib];

    //we have no overlapping views
    //[[self window] useOptimizedDrawing: YES];

    [self setPostsFrameChangedNotifications: YES];

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	//we want to know if we were resized
    [nc addObserver: self
		   selector: @selector(viewFrameDidChangeNotification:)
			   name: NSViewFrameDidChangeNotification
			 object: self];
	
	//these 2 notifications are sent by our window when it gains or looses focus
    [nc addObserver: self
		   selector: @selector(windowDidResignKey:)
			   name: NSWindowDidResignKeyNotification
			 object: [self window]];	
    [nc addObserver: self
		   selector: @selector(windowDidBecomeKey:)
			   name: NSWindowDidBecomeKeyNotification
			 object: [self window]];
	
    return self;
}

- (void) awakeFromNib
{
    [[self window] setAcceptsMouseMovedEvents: YES];

    //we will defer the creation fo the renderers till "reloadData" is called explicitly
    //_rootItemRenderer = [[TMVItem alloc] initWithDataSource: dataSource delegate: delegate renderedItem: nil treeMapView: self];
}

- (void) dealloc
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    //remove ourself as observer for the NSViewFrameDidChangeNotification
    [nc removeObserver: self];

    //remove our delegate for all our notifications
    if ( delegate != nil )
        [nc removeObserver: delegate name:nil object:self];

    [_rootItemRenderer release];
    [self deallocContentCache]; 

    [super dealloc];
}

- (id) delegate
{
    return delegate;
}

- (void) setDelegate: (id) new_delegate
{
    NSParameterAssert( new_delegate != nil );
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    if ( delegate != nil )
        [nc removeObserver: delegate name:nil object:self];

    delegate = new_delegate;

    // register our delegate as observer for all our notifications
#define REGISTER_DELEGATE( method, notification ) \
    if ([delegate respondsToSelector:@selector(method:)]) \
        [nc addObserver: delegate selector: @selector(method:) \
               name: notification object:self]

    REGISTER_DELEGATE( treeMapViewSelectionDidChange,	TreeMapViewSelectionDidChangedNotification );
    REGISTER_DELEGATE( treeMapViewSelectionIsChanging,	TreeMapViewSelectionIsChangingNotification );
    REGISTER_DELEGATE( treeMapViewItemTouched,		TreeMapViewItemTouchedNotification );

#undef REGISTER_DELEGATE
}

- (void) setDataSource: (id) new_dataSource
{
    dataSource = new_dataSource;

    //check that the data source implements all the required methods of category NSObject(TreeMapViewDataSource)
#define RAISE_EXCEPTION( method ) \
        [NSException raise:NSInternalInconsistencyException \
                    format:@"data source doesn't respond to '%@'", method]

    if ( ![ dataSource respondsToSelector:@selector(treeMapView: child: ofItem:) ] )
        RAISE_EXCEPTION( @"(id) treeMapView: (TreeMapView*) view child: (unsigned) index ofItem: (id) item" );
        
    if ( ![ dataSource respondsToSelector:@selector(treeMapView: isNode:) ] )
        RAISE_EXCEPTION( @"(BOOL) treeMapView: (TreeMapView*) view isNode: (id) item" );
    
    if ( ![ dataSource respondsToSelector:@selector(treeMapView: numberOfChildrenOfItem:) ] )
        RAISE_EXCEPTION( @"(unsigned) treeMapView: (TreeMapView*) view numberOfChildrenOfItem: (id) item" );
    
    if ( ![ dataSource respondsToSelector:@selector(treeMapView: weightByItem:) ] )
        RAISE_EXCEPTION( @"(unsigned long long) treeMapView: (TreeMapView*) view weightByItem: (id) item" );
        
#undef RAISE_EXCEPTION
}

- (void) drawRect: (NSRect) rect
{
	//first, draw the focus rect, if we are first responder
	if ( [[self window] isKeyWindow]
		 && [[self window] firstResponder] == self )
	{
		[NSGraphicsContext saveGraphicsState];
		
		NSSetFocusRingStyle( NSFocusRingOnly );
		
		[[NSColor keyboardFocusIndicatorColor] set];		
		NSFrameRectWithWidth( [self visibleRect], 1 ); 
		
		[NSGraphicsContext restoreGraphicsState];
	}
	
	//If the window is being resized, we don't draw the tree map (too slow).
	//same for the case that we don't have anything to draw
    if ( [self inLiveResize] || _rootItemRenderer == nil || [_rootItemRenderer childCount] == 0 )
    {
        //NSDrawWindowBackground( rect );
        NSEraseRect( rect );
        return;
    }
	
	if ( _zoomer != nil )
	{
		[_zoomer drawImage];
		return;
	}

    //if our size has changed, re-layout items
    NSRect viewBounds = [self bounds];
    BOOL relayout = !NSEqualRects( viewBounds, [_rootItemRenderer rect] );
    if ( relayout )
    {
        [_rootItemRenderer calcLayout: viewBounds];
 
        [self deallocContentCache];
    }
	
    [self drawInCache];

    NSSize imageSize = NSMakeSize( NSWidth(viewBounds), NSHeight(viewBounds) );

    NSImage *image = [_cachedContent suitableImageForView: self];

    [image drawAtPoint: NSMakePoint( 0, 0 )
              fromRect: viewBounds
             operation: NSCompositeCopy
              fraction: 1];

    if ( _selectedRenderer != nil )
    {
        [_selectedRenderer drawHighlightFrame];
    }
	
}
	
- (void) mouseDown: (NSEvent*) theEvent
{
    NSPoint point = [theEvent locationInWindow];
    point = [self convertPoint: point fromView: nil];
    point.y--;

    //find the hitted item
    TMVItem* renderer = [_rootItemRenderer hitTest: point];

    if ( renderer != _selectedRenderer )
    {
        _selectedRenderer = renderer;
        
        //post notification
        [[NSNotificationCenter defaultCenter] postNotificationName: TreeMapViewSelectionDidChangedNotification object: self userInfo: nil];

        [self setNeedsDisplay: YES];
    }
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
	if ( [self acceptsFirstResponder]
		 && [[self window] firstResponder] != self )
	{
		[[self window] makeFirstResponder: self];
	}
	
	[super rightMouseDown: theEvent];
}

- (void) mouseMoved: (NSEvent *)theEvent
{
    [super mouseMoved: theEvent];
    
    NSPoint point = [theEvent locationInWindow];
    point = [self convertPoint: point fromView: nil];
    point.y--;

    //first test if the mouse is still in the same item
    if ( _touchedRenderer != nil && [_touchedRenderer hitTest: point] != nil )
        return;

    //the mouse is moved to a new item, so look for the new one
     TMVItem* renderer = [_rootItemRenderer hitTest: point];

    if ( renderer == _touchedRenderer )
    {
        NSAssert( renderer == nil, @"why this?" );
        return;
    }

    _touchedRenderer = renderer;

    id touchedItem = (_touchedRenderer == nil) ? nil : [_touchedRenderer item];

    //set tooltip
    NSString *toolTip = nil;
    if ( touchedItem != nil && [delegate respondsToSelector: @selector(treeMapView: getToolTipByItem:)] )
        toolTip = [delegate treeMapView: self getToolTipByItem: touchedItem];

    [self setToolTip: toolTip];

    //post notification about the touched item
    NSDictionary *userInfo = (touchedItem == nil) ?
        [NSDictionary dictionary] : [NSDictionary dictionaryWithObject: touchedItem forKey: TMVTouchedItem];
    
    [[NSNotificationCenter defaultCenter] postNotificationName: TreeMapViewItemTouchedNotification object: self userInfo: userInfo];
}

- (NSMenu*) menuForEvent: (NSEvent*) event
{
    if ( [delegate respondsToSelector: @selector(treeMapView: willShowMenuForEvent:)] )
        [delegate treeMapView: self willShowMenuForEvent: event];

    return [super menuForEvent: event];
}


- (TMVCellId) cellIdByPoint: (NSPoint) point inViewCoords: (BOOL) viewCoords;
{
    if ( !viewCoords)
        point = [self convertPoint: point fromView: nil];

    return [_rootItemRenderer hitTest: point];
}

- (id) selectedItem
{
    return _selectedRenderer == nil ? nil : [_selectedRenderer item];
}

- (id) itemByCellId: (TMVCellId) cellId
{
    NSParameterAssert( cellId != nil );

    return [cellId item];
}

- (void) selectItemByCellId: (TMVCellId) cellId
{
    if ( cellId != _selectedRenderer )
    {
        _selectedRenderer = cellId;

        //post notification
        [[NSNotificationCenter defaultCenter] postNotificationName: TreeMapViewSelectionDidChangedNotification object: self userInfo: nil];

        [self setNeedsDisplay: YES];
    }
}

- (void) selectItemByPathToItem: (NSArray*) path
{
    //path must at least contain one item (the root item)
	NSAssert( [path count] > 0, @"path must contain at least 1 component" );
    
	TMVItem *rendererToSelect = [self findTMVItemByPathToDataItem: path];

	if ( rendererToSelect != nil )
		[self selectItemByCellId: rendererToSelect];
}

- (NSRect) itemRectByCellId: (TMVCellId) cellId
{
	NSParameterAssert( cellId != nil );
	
	if ( cellId != nil )
		return [cellId rect];
	else
		return NSZeroRect;
}

//rect in view coords; item is identified by path from root to item in question
- (NSRect) itemRectByPathToItem: (NSArray*) path
{
    //path must at least contain one item (the root item)
	NSAssert( [path count] > 0, @"path must contain at least 1 component" );
    
	TMVItem *renderer = [self findTMVItemByPathToDataItem: path];
	
	if ( renderer != nil )
		return [renderer rect];
	else
		return NSZeroRect;
}

- (void) reloadData
{
    [self deallocContentCache];

    [_rootItemRenderer release];

    _selectedRenderer = nil;
    _touchedRenderer = nil;

    _rootItemRenderer = [[TMVItem alloc] initWithDataSource: dataSource delegate: delegate renderedItem: nil treeMapView: self];

    [self removeAllToolTips];
    [self addToolTipRect: [self bounds] owner: self userData: nil];
    
    [self setNeedsDisplay: YES];
}

- (void) reloadAndPerformZoomIntoItem: (NSArray*) path
{
    //path must at least contain one item (the root item)
	NSAssert( [path count] > 0, @"path must contain at least 1 component" );
	
	NSRect viewBounds = [self bounds];
	
	//just reload if item to zoom in is too small
	TMVItem *renderer = [self findTMVItemByPathToDataItem: path];
	if ( renderer == nil
		 || NSEqualRects( viewBounds, [renderer rect] )
		 || NSWidth([renderer rect]) <= 4 || NSHeight([renderer rect]) <= 4 )
	{
		if ( renderer == nil )
			NSLog( @"item to zoom in wasn't found" );
		[self reloadData];
		return;
	}
	
	NSBitmapImageRep *oldImageRep = nil;
	if ( _cachedContent == nil )
	{
		//creates a Bitmap with 24 bit color depth and no alpha component							 
		oldImageRep = [[ NSBitmapImageRep alloc]
						initRGBBitmapWithWidth: NSWidth(viewBounds) height: NSHeight(viewBounds)];
		
		[_rootItemRenderer calcLayout: viewBounds];
		[_rootItemRenderer drawCushionInBitmap: oldImageRep];
	}
	else
		oldImageRep = [_cachedContent retain];
	
	[oldImageRep autorelease];
	
	//before we animate the zooming, make sure the new content is loaded and rendered,
	//so the new content can be drawn immediately after the zooming has finished
	[self reloadData];
	[_rootItemRenderer calcLayout: viewBounds];
	[self deallocContentCache];
	[self drawInCache];
	
	//was set to YES in reloadData
	[self setNeedsDisplay: NO];
	
	_zoomer = [[ZoomInfo alloc] initWithImage: [oldImageRep suitableImageForView: self]
									 delegate: self
									 selector: @selector(performZoom:)];
	[_zoomer calculateZoomFromRect: [renderer rect] toRect: viewBounds];
}

- (void) reloadAndPerformZoomOutofItem: (NSArray*) path
{
    //path must at least contain one item (the root item)
	NSAssert( [path count] > 0, @"path must contain at least 1 component" );
	
	NSRect viewBounds = [self bounds];
	
	//reload and render content
	[self reloadData];
	[_rootItemRenderer calcLayout: viewBounds];
	[self deallocContentCache];
	[self drawInCache];
	
	//do nothing if item to zoom in is too small
	TMVItem *renderer = [self findTMVItemByPathToDataItem: path];
	if ( renderer == nil
		 || NSEqualRects( viewBounds, [renderer rect] )
		 || NSWidth([renderer rect]) <= 4 || NSHeight([renderer rect]) <= 4 )
	{
		if ( renderer == nil )
			NSLog( @"item to zoom in wasn't found" );
		return;
	}
	
	//was set to YES in reloadData
	[self setNeedsDisplay: NO];
	
	_zoomer = [[ZoomInfo alloc] initWithImage: [_cachedContent suitableImageForView: self]
									 delegate: self
									 selector: @selector(performZoom:)];
	[_zoomer calculateZoomFromRect: viewBounds toRect: [renderer rect]];
}

- (NSString *) view: (NSView *) view stringForToolTip: (NSToolTipTag) tag point: (NSPoint) point userData: (void *) userData
{
    if ( delegate != nil && [delegate respondsToSelector: @selector(treeMapView: getToolTipByItem:)] )
    {
        TMVItem *childRenderer = [self cellIdByPoint: point inViewCoords: YES];

        return [delegate treeMapView: self getToolTipByItem: [childRenderer item]];
    }
    else
        return @"";
}

- (void) viewDidEndLiveResize
{
    [self addToolTipRect: [self bounds] owner: self userData: nil];
    
    [self setNeedsDisplay: YES];
}

- (void) viewWillStartLiveResize
{
    [self removeAllToolTips];
}

- (void) viewFrameDidChangeNotification: (NSNotification*) notification
{
	if ( ![self inLiveResize] )
	{
	    [self removeAllToolTips];
		[self addToolTipRect: [self bounds] owner: self userData: nil];
	}
}

- (BOOL) isFlipped
{
    return YES;
}

- (BOOL) acceptsFirstResponder
{
    return YES;
}

//we're about to get the input focus, so invalidate the area of the focus rect
- (BOOL) becomeFirstResponder
{
	if ( ![super resignFirstResponder] )
		return NO;
	
	[self setKeyboardFocusRingNeedsDisplayInRect: [self visibleRect]];
	
	return YES;
}

//we're about to loose the input focus, so invalidate the area of the focus rect
- (BOOL) resignFirstResponder
{
	if ( ![super resignFirstResponder] )
		return NO;
	
	[self setKeyboardFocusRingNeedsDisplayInRect: [self visibleRect]];
	
	return YES;
}

//our window is no longer key, so invalidate the area of our focus rect
- (void) windowDidResignKey: (NSNotification *)aNotification
{
	if ( [[self window] firstResponder] == self )
		[self setKeyboardFocusRingNeedsDisplayInRect: [self visibleRect]];
}

//our window has become key, so invalidate the area of our focus rect
- (void) windowDidBecomeKey: (NSNotification *) aNotification
{
	if ( [[self window] firstResponder] == self )
		[self setKeyboardFocusRingNeedsDisplayInRect: [self visibleRect]];
}

- (BOOL) canBecomeKeyView
{
	return YES;
}

- (BOOL) isOpaque
{
    return YES;
}

- (void) benchmarkLayoutCalculationWithImageSize: (NSSize) size count: (unsigned) count
{
	TMVItem *tmvItem = [[TMVItem alloc] initWithDataSource: dataSource delegate: delegate renderedItem: nil treeMapView: self];
	
	count /= 2;
	
	NSSize size2 = NSMakeSize( size.width * 2, size.height *2 );

	for ( ; count > 0; count-- )
	{
		[tmvItem calcLayout: NSMakeRect(0, 0, size.width, size.height)];
		[tmvItem calcLayout: NSMakeRect(0, 0, size2.width, size2.height)];
	}
	
	[tmvItem release];
}

- (void) benchmarkRenderingWithImageSize: (NSSize) size count: (unsigned) count
{
	//creates a Bitmap with 24 bit color depth and no alpha component							 
    NSBitmapImageRep *bitmap = [[ NSBitmapImageRep alloc]
								initRGBBitmapWithWidth: size.width height: size.height];
	
	TMVItem *tmvItem = [[TMVItem alloc] initWithDataSource: dataSource delegate: delegate renderedItem: nil treeMapView: self];
	[tmvItem calcLayout: NSMakeRect(0, 0, size.width, size.height)];
	
	for ( ; count > 0; count-- )
	{
		[tmvItem drawCushionInBitmap: bitmap];
	}
	
	[tmvItem release];
	[bitmap release];
}

@end

//================ implementation TreeMapView(Private) ======================================================

@implementation TreeMapView(Private)

- (void) drawInCache
{
    if ( _cachedContent != nil )
        return;

    [self allocContentCache];

	if ( _rootItemRenderer != NULL )
	{
		[_rootItemRenderer drawCushionInBitmap: _cachedContent];
	}
}

- (void) allocContentCache
{
    [_cachedContent release];

    NSRect viewBounds = [self bounds];

	//creates a Bitmap with 24 bit color depth and no alpha component							 
    _cachedContent = [[ NSBitmapImageRep alloc]
						initRGBBitmapWithWidth: NSWidth(viewBounds) height: NSHeight(viewBounds)];
}

- (void) deallocContentCache
{
    if ( _cachedContent != nil )
    {
        [_cachedContent release];
        _cachedContent = nil;
    }
}

- (TMVItem*) findTMVItemByPathToDataItem: (NSArray*) path
{
	if ( _rootItemRenderer == nil )
		return nil;
	
	NSAssert( [path count] > 0, @"path must contain at least 1 component" );
	
	TMVItem *parent = _rootItemRenderer;
	TMVItem *child = _rootItemRenderer;
	
	NSEnumerator *pathEnum = [path objectEnumerator];
	[pathEnum nextObject]; //we start with the second item, as the first corresponds to our root
	
	id dataItem;
	while( (dataItem = [pathEnum nextObject]) != nil )
	{
		NSEnumerator *childEnum = [parent childEnumerator];
		
		//find renderer displaying "dataItem"
		while ( (child = [childEnum nextObject]) != nil && [child item] != dataItem );
		
		if ( child == nil )
			return nil; //not found
		
		parent = child;
	}
	
	return child;
}
/*
- (void) onZoomTimer: (NSTimer*) timer
{
	NSAssert( timer == _zoomTimer, @"unknown timer" );
	NSAssert( [timer isValid], @"invalid timer" );
	
	ZoomInfo *zoomInfo = [_zoomTimer userInfo];
	
	[zoomInfo decrementStepCount];
	[zoomInfo calculateNewRect];
	
	[self display];
	
	if ( [zoomInfo zoomStepsLeft] <= 0 )
	{
		[_zoomTimer invalidate];
		[_zoomTimer release];
		_zoomTimer = nil;
		
		[self setNeedsDisplay: YES];
	}	
}
*/
- (void) performZoom: (ZoomInfo*) zoomInfo
{
	NSParameterAssert( _zoomer == zoomInfo );

	[self display];
		
	if ( [zoomInfo hasFinished] )
	{
		[_zoomer release];
		_zoomer = nil;
		
		[self setNeedsDisplay: YES];
	}
}

@end
