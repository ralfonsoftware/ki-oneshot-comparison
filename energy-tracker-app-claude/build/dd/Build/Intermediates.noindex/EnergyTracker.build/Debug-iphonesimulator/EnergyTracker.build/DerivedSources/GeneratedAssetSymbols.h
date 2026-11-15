#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"de.ralfonsoftware.EnergyTracker";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "StatusBelowBaseline" asset catalog color resource.
static NSString * const ACColorNameStatusBelowBaseline AC_SWIFT_PRIVATE = @"StatusBelowBaseline";

/// The "StatusBelowBaselineText" asset catalog color resource.
static NSString * const ACColorNameStatusBelowBaselineText AC_SWIFT_PRIVATE = @"StatusBelowBaselineText";

/// The "StatusTrending" asset catalog color resource.
static NSString * const ACColorNameStatusTrending AC_SWIFT_PRIVATE = @"StatusTrending";

/// The "StatusTrendingText" asset catalog color resource.
static NSString * const ACColorNameStatusTrendingText AC_SWIFT_PRIVATE = @"StatusTrendingText";

/// The "StatusWithinRange" asset catalog color resource.
static NSString * const ACColorNameStatusWithinRange AC_SWIFT_PRIVATE = @"StatusWithinRange";

/// The "StatusWithinRangeText" asset catalog color resource.
static NSString * const ACColorNameStatusWithinRangeText AC_SWIFT_PRIVATE = @"StatusWithinRangeText";

/// The "WidgetBackground" asset catalog color resource.
static NSString * const ACColorNameWidgetBackground AC_SWIFT_PRIVATE = @"WidgetBackground";

#undef AC_SWIFT_PRIVATE
