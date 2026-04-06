#import <UIKit/UIKit.h>
#import <FirebaseCore/FirebaseCore.h>

// Configure before UIApplicationMain so FIRApp exists before Flutter plugin
// registration (e.g. FirebaseFunctionsPlugin) and before any Swift paths that
// touch FirebaseApp.app().
int main(int argc, char * argv[]) {
  @autoreleasepool {
    // Do not call [FIRApp defaultApp] before configure — that can emit I-COR000003.
    [FIRApp configure];
    return UIApplicationMain(argc, argv, nil, @"AppDelegate");
  }
}
