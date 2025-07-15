//
// AppDelegate.m
//
// Copyright (c) 2020-2025 Larry M. Taylor
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software. Permission is granted to anyone to
// use this software for any purpose, including commercial applications, and to
// to alter it and redistribute it freely, subject to 
// the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source
//    distribution.
//

#import "AppDelegate.h"
#import "NSFileManager+DirectoryLocations.h"

@implementation AppDelegate

@synthesize mTextField;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Set up logging
    mLog = os_log_create("com.larrymtaylor.StandaloneHostUpdater",
                         "AppDelegate");
    NSString *path =
        [[NSFileManager defaultManager] applicationSupportDirectory];
    mLogFile = [[NSString alloc] initWithFormat:@"%@/logFile.txt", path];
    UInt64 fileSize = [[[NSFileManager defaultManager]
                        attributesOfItemAtPath:mLogFile error:nil] fileSize];

    if (fileSize > (1024 * 1024))
    {
        [[NSFileManager defaultManager] removeItemAtPath:mLogFile error:nil];
    }
 
    // Set colors
    [self.window setBackgroundColor:[NSColor colorWithRed:0.2
                                     green:0.2 blue:0.2 alpha:1.0]];
    [mTextField setBackgroundColor:[NSColor colorWithRed:0.2
                                    green:0.2 blue:0.2 alpha:1.0]];
    [mTextField setTextColor:[NSColor whiteColor]];

    // Initialize variables
    mCopyCount = 0;
    mUpdatePassed = 0;
    mUpdateFailed = 0;
    mInstalledAppList = [[NSMutableArray alloc] init];
    mHostApp = [[NSURL alloc] initWithString:@""];
    
    // Display start indication
    mText = [[NSMutableString alloc] initWithString:
        @"Searching for StandaloneHost.app and any renamed copies.\n\n"];
    [mTextField setStringValue:mText];

    // Get macOS version
    mVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    mSystemVersion = [NSString stringWithFormat:@"%ld.%ld",
                      mVersion.majorVersion, mVersion.minorVersion];
 
    // Log some basic information
    NSBundle *appBundle = [NSBundle mainBundle];
    NSDictionary *appInfo = [appBundle infoDictionary];
    NSString *appVersion = [appInfo objectForKey:@"CFBundleShortVersionString"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yyyy h:mm a"];
    NSString *day = [dateFormatter stringFromDate:[NSDate date]];

    LTLog(mLog, mLogFile, OS_LOG_TYPE_INFO,
          @"\nStandaloneHostUpdater v%@ running on macOS %@ (%@)",
          appVersion, mSystemVersion, day);

    // Start task to get app list
    mReady = false;
    [self getAppList];

    // Start timer to wait for app list ready
    mReadyTimer = [NSTimer scheduledTimerWithTimeInterval:1
                   target:self selector:@selector(readyTimerOne:)
                   userInfo:nil repeats:YES];
}

- (void)getAppList
{
	NSOperationQueue *queue = [[NSOperationQueue alloc] init];
	[queue addOperationWithBlock:^{

        // Get a list of all installed apps
        NSMutableString *dir1 = [[NSMutableString alloc] init];
        NSMutableString *dir2 = [[NSMutableString alloc] init];
    
        if (([self->mSystemVersion isEqualToString:@"10.15"]) ||
            (self->mVersion.majorVersion >= 11))
        {
            [dir1 appendString:@"/System/Applications"];
            [dir2 appendString:@"/System/Volumes/Data/Applications"];
        }
        else
        {
            [dir1 appendString:@"/Applications"];
            [dir2 appendString:NSHomeDirectory()];
            [dir2 appendString:@"/Applications"];
        }
    
        NSURL *dir1Url = [[NSURL alloc] initWithString:dir1];
        NSDirectoryEnumerator *enumerator1 = [[NSFileManager defaultManager]
            enumeratorAtURL:[dir1Url URLByResolvingSymlinksInPath]
            includingPropertiesForKeys:nil
            options:NSDirectoryEnumerationSkipsPackageDescendants
            errorHandler:nil];
    
        for (NSURL *url in enumerator1)
        {
            if ([[[url lastPathComponent] pathExtension] 
                   isEqualToString:@"app"])
            {
                if ([[url lastPathComponent] 
                      isEqualToString:@"StandaloneHost.app"])
                {
                    self->mHostApp = [url copy];
                }
                else
                {
                    NSBundle *bundle = [NSBundle bundleWithURL:url];
                    NSString *ident = [bundle bundleIdentifier];
            
                    if ([ident isEqualToString:
                         @"com.larrymtaylor.StandaloneHost"])
                    {
                        [self->mInstalledAppList addObject:url];
                        ++self->mCopyCount;
                    }
                }
            }
        }
      
        NSURL *dir2Url = [[NSURL alloc] initWithString:dir2];
        NSDirectoryEnumerator *enumerator2 = [[NSFileManager defaultManager]
            enumeratorAtURL:[dir2Url URLByResolvingSymlinksInPath]
            includingPropertiesForKeys:nil
            options:NSDirectoryEnumerationSkipsPackageDescendants
            errorHandler:nil];
    
        for (NSURL *url in enumerator2)
        {
            if ([[[url lastPathComponent] pathExtension]
                   isEqualToString:@"app"])
            {
                if ([[url lastPathComponent]
                      isEqualToString:@"StandaloneHost.app"])
                {
                    self->mHostApp = [url copy];
                }
                else
                {
                    NSBundle *bundle = [NSBundle bundleWithURL:url];
                    NSString *ident = [bundle bundleIdentifier];
            
                    if ([ident isEqualToString:
                         @"com.larrymtaylor.StandaloneHost"])
                    {
                        [self->mInstalledAppList addObject:url];
                        ++self->mCopyCount;
                    }
                }
            }
        }

        self->mReady = true;
	}];
}

- (void)readyTimerOne:(NSTimer *)timer
{
    if (mReady == false)
    {
        return;
    }
    
    [mReadyTimer invalidate];
    mReadyTimer = nil;

    // Make sure we have an unnamed copy to use for updating
    if ([[mHostApp absoluteString] isEqualToString:@""] == YES)

    {
        [mText appendString:@"StandaloneHost.app not found!"];
        [mTextField setStringValue:mText];
        LTLog(mLog, mLogFile, OS_LOG_TYPE_ERROR,
              @"StandaloneHost.app not found!");
    }
    else
    {
        [mText appendString:@"Found StandaloneHost.app at "];
        [mText appendString:[mHostApp path]];
        [mText appendFormat:@"\nand %i renamed copies.\n\n", mCopyCount];
        [mTextField setStringValue:mText];
        LTLog(mLog, mLogFile, OS_LOG_TYPE_INFO,
              @"Found StandaloneHost.app at %@ and %i renamed copies.",
              [mHostApp path], mCopyCount);

        // Start task to update copies
        mReady = false;
        [self updateCopies];

        // Start timer to wait for update complete
        mReadyTimer = [NSTimer scheduledTimerWithTimeInterval:1
                       target:self selector:@selector(readyTimerTwo:)
                       userInfo:nil repeats:YES];
    }
}

- (void)updateCopies
{
	NSOperationQueue *queue = [[NSOperationQueue alloc] init];
	[queue addOperationWithBlock:^{

        // Update each copy
        NSFileManager *manager = [NSFileManager defaultManager];
        NSError *error = nil;

        for (NSURL *url in self->mInstalledAppList)
        {
            [manager removeItemAtURL:url error:&error];
        
            if (error == nil)
            {
                [manager copyItemAtURL:self->mHostApp toURL:url error:&error];
    
                if (error == nil)
                {
                    ++self->mUpdatePassed;
                    LTLog(self->mLog, self->mLogFile, OS_LOG_TYPE_INFO,
                          @"Updated %@", [url path]);
                }
                else
                {
                    ++self->mUpdateFailed;
                    LTLog(self->mLog, self->mLogFile, OS_LOG_TYPE_INFO,
                          @"Could not update %@, error = ",
                          [url path], [error localizedDescription]);
                }
            }
            else
            {
                ++self->mUpdateFailed;
                LTLog(self->mLog, self->mLogFile, OS_LOG_TYPE_INFO,
                      @"Could not delete %@, error = ",
                      [url path], [error localizedDescription]);
            }
        }

        self->mReady = true;
	}];
}
    
- (void)readyTimerTwo:(NSTimer *)timer
{
    if (mReady == false)
    {
        return;
    }

    [mReadyTimer invalidate];
    mReadyTimer = nil;

    [mText appendFormat:@"Successfully updated %i copies.\n", mUpdatePassed];
    
    if (mUpdateFailed > 0)
    {
        [mText appendFormat:@"Could not update %i copies.", mUpdateFailed];
    }
      
    [mText appendString:
     @"\nPlease quit this application if installing StandaloneHost."];
    [mTextField setStringValue:mText];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return TRUE;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
}

@end
