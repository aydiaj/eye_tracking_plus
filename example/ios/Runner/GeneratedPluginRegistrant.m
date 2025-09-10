//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<eye_tracking_plus/EyeTrackingPlugin.h>)
#import <eye_tracking_plus/EyeTrackingPlugin.h>
#else
@import eye_tracking_plus;
#endif

#if __has_include(<integration_test/IntegrationTestPlugin.h>)
#import <integration_test/IntegrationTestPlugin.h>
#else
@import integration_test;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [EyeTrackingPlugin registerWithRegistrar:[registry registrarForPlugin:@"EyeTrackingPlugin"]];
  [IntegrationTestPlugin registerWithRegistrar:[registry registrarForPlugin:@"IntegrationTestPlugin"]];
}

@end
