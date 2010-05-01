//
//  NSBitmapImageRep-Extensions.m
//  TreeMapView
//
//  Created by Tjark Derlien on 20.10.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//

#import "NSBitmapImageRep-CreationExtensions.h"

@implementation NSBitmapImageRep (CreationExtensions)

//creates a Bitmap with 24 bit color depth and no alpha component
- (id) initRGBBitmapWithWidth: (int) width height: (int) height
{
	return [self initWithBitmapDataPlanes: NULL    // Let the class allocate it
							   pixelsWide: width
							   pixelsHigh: height
							bitsPerSample: 8       // Each component is 8 bits (one byte)
						  samplesPerPixel: 3       // Number of components (R, G, B, no alpha)
								 hasAlpha: NO
								 isPlanar: NO
						   colorSpaceName: NSCalibratedRGBColorSpace
							  bytesPerRow: 0       // 0 means: Let the class figure it out
							 bitsPerPixel: 0];     // 0 means: Let the class figure it out
}

//creates an autoreleased NSImage with the samme dimensions as the NSBitmapImageRep
//and adds the NSBitmapImageRep as the only image represensation;
//set flipped coordinates if "view" is flipped
- (NSImage*) suitableImageForView: (NSView*) view
{
    NSImage *image = [[NSImage alloc] initWithSize: [self size]];
	
    [image addRepresentation: self];
    [image setFlipped: [view isFlipped]];
	
	return [image autorelease];
}

@end
