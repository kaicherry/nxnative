// Joy-Con Probe: what iOS's GameController hands an app for a paired controller.
//
// The Mac host reads an original (Switch 1) Joy-Con's sensor itself because macOS's GameController
// gives a pair no GCMotion at all and its HID report carries the IMU fields zeroed
// (docs/reference/services.md, "An original Joy-Con's sensors are read by the host"). That transport
// is IOKit and cannot run on iOS, so the question for the iPad is a different one: does iOS's
// GameController expose the gyroscope of a paired Joy-Con through GCMotion? If it does, the iOS app
// already uses it (dm/host/motion_apple.h) and nothing needs writing; if it does not, no public API
// reaches the sensor.
//
// Pair the controller in Settings > Bluetooth first (iOS 16 and later list Joy-Con (L) and (R) as
// gamepads), then open this app: it prints every controller, what its motion object offers, and the
// acceleration and rotation it delivers. "Scan" starts wireless controller discovery again.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

static UITextView *g_text;
static NSMutableString *g_log;
static NSString *g_file;

static void emit(NSString *line) {
    NSString *stamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                    dateStyle:NSDateFormatterNoStyle
                                                    timeStyle:NSDateFormatterMediumStyle];
    NSString *s = [NSString stringWithFormat:@"%@  %@\n", stamp, line];
    g_log = g_log ?: [NSMutableString new];
    [g_log appendString:s];
    dispatch_async(dispatch_get_main_queue(), ^{
        g_text.text = g_log;
        [g_text scrollRangeToVisible:NSMakeRange(g_text.text.length, 0)];
    });
    [g_log writeToFile:g_file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSLog(@"[joycon-probe] %@", line);
}

static NSString *fmt(const float v[3]) {
    return [NSString stringWithFormat:@"%+.3f %+.3f %+.3f", v[0], v[1], v[2]];
}

static void describe(GCController *c, const char *why) {
    GCMotion *m = c.motion;
    emit([NSString stringWithFormat:@"%s: %@ / vendor \"%@\" / category \"%@\" / player %ld",
          why, c, c.vendorName ?: @"-", c.productCategory ?: @"-", (long)c.playerIndex]);
    emit([NSString stringWithFormat:@"   buttons %lu, axes %lu, battery %.2f",
          (unsigned long)c.physicalInputProfile.buttons.count,
          (unsigned long)c.physicalInputProfile.axes.count,
          c.battery ? c.battery.batteryLevel : -1.0f]);
    if (!m) {
        emit(@"   motion: none (no GCMotion object) -- the app cannot see a gyroscope");
        return;
    }
    emit([NSString stringWithFormat:@"   motion: present, rotationRate %d, gravity+userAccel %d, "
                                    @"attitude %d, manualActivation %d",
          m.hasRotationRate, m.hasGravityAndUserAcceleration, m.hasAttitude,
          m.sensorsRequireManualActivation]);
    if (m.sensorsRequireManualActivation) {
        m.sensorsActive = YES;                      // DualSense / DualShock 4: off until asked for
        emit([NSString stringWithFormat:@"   sensorsActive set to YES (now %d)", m.sensorsActive]);
    }
}

static void watch(GCController *c) {
    GCMotion *m = c.motion;
    if (!m) return;
    __block int live = 0;
    m.valueChangedHandler = ^(GCMotion *mm) {
        float acc[3], rot[3];
        if (mm.hasGravityAndUserAcceleration) {
            GCAcceleration g = mm.gravity, u = mm.userAcceleration;
            acc[0] = (float)(g.x + u.x); acc[1] = (float)(g.y + u.y); acc[2] = (float)(g.z + u.z);
        } else {
            acc[0] = acc[1] = acc[2] = 0;
        }
        if (mm.hasRotationRate) {
            GCRotationRate r = mm.rotationRate;
            rot[0] = (float)r.x; rot[1] = (float)r.y; rot[2] = (float)r.z;
        } else {
            rot[0] = rot[1] = rot[2] = 0;
        }
        live++;
        if (live == 1 || live % 30 == 0) {          // about twice a second at a pad's rate
            BOOL still = fabs(rot[0]) + fabs(rot[1]) + fabs(rot[2]) < 0.02f;
            emit([NSString stringWithFormat:@"   [%d] acc %@ G  rot %@ rev/s%@", live, fmt(acc), fmt(rot),
                  still ? @"  (still)" : @""]);
        }
    };
}

static void scan(void) {
    [[GCController controllers] enumerateObjectsUsingBlock:^(GCController *c, NSUInteger i, BOOL *stop) {
        describe(c, "already connected");
        watch(c);
    }];
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{
        emit(@"discovery finished");
    }];
    emit(@"wireless controller discovery started -- hold a button on the controller; "
         @"a controller paired in Settings appears without this");
}

@interface ProbeViewController : UIViewController
@end
@implementation ProbeViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    g_file = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0]
              stringByAppendingPathComponent:@"joycon-probe.log"];
    g_text = [[UITextView alloc] initWithFrame:CGRectInset(self.view.bounds, 8, 40)];
    g_text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    g_text.editable = NO;
    g_text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.view addSubview:g_text];

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(8, self.view.bounds.size.height - 34, 120, 30);
    b.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [b setTitle:@"Scan again" forState:UIControlStateNormal];
    [b addTarget:self action:@selector(rescan) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *n) {
        describe(n.object, "connected");
        watch(n.object);
    }];
    [nc addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *n) {
        emit([NSString stringWithFormat:@"disconnected: %@", n.object]);
    }];
    emit([NSString stringWithFormat:@"iOS %@ -- log also in Documents/joycon-probe.log",
          [[UIDevice currentDevice] systemVersion]]);
    scan();
}
- (void)rescan { scan(); }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ProbeViewController class]));
    }
}
