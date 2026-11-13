# Joy-Con Probe

Answers one question before anyone writes an iOS transport: **does iOS's GameController hand an
app a paired original (Switch 1) Joy-Con's gyroscope?**

On the Mac it does not: a pair arrives as one `GCController` with no `GCMotion`, and its HID report
carries the IMU fields zeroed until the host asks for the sensor itself, which is why the Mac
transport exists (`dm/host/pad_jc1.h`, `pad_jc1_mac.h`; [the reference
entry](../../../docs/reference/services.md#an-original-joy-cons-sensors-are-read-by-the-host)). That
transport is IOKit, so it cannot run on iOS, and CoreBluetooth cannot help: an original Joy-Con is
Bluetooth Classic HID, not BLE.

The iOS app already reads `GCMotion` (`dm/host/motion_apple.h`, shared with the Mac front end), so
if iOS does expose the sensor there is nothing to write.

## Build and run

```sh
dm/ios/tools/joycon_probe/build.sh /Volumes/X9BS/joycon-probe   # -> JoyConProbe.ipa (48 KB)
```

Pair the controller in Settings > Bluetooth first (iOS 16 and later list Joy-Con (L) and Joy-Con
(R) as gamepads; a pair is one controller), install the IPA (with a real certificate sign the
bundle and embed your profile, as with any app; the build is signing-agnostic), and open the app.
It prints:

- every controller with its vendor name, product category and player slot;
- what its motion object offers (`rotationRate`, `gravity+userAcceleration`, `attitude`,
  `sensorsRequireManualActivation`), or that there is no `GCMotion` at all;
- the acceleration and rotation it delivers, about twice a second, with `(still)` on a pad at rest.

The same lines go to `Documents/joycon-probe.log` (Files app: On My iPad > Joy-Con Probe), which
is the thing to send back.

## What each answer means

- **Motion present and moving** — the iOS app needs nothing: a Joy-Con's gyro reaches it through
  the path the Mac already uses, and a game on the iPad follows the pad. The remaining work is an
  iOS build of the game (`scripts/build_ipa_from_nsp.py --platform ios`).
- **Motion present, zeros** — Apple's driver advertises it and does not fill it, as it does on the
  Mac for the Switch Pro Controller ([that
  entry](../../../docs/reference/services.md#switch-pro-controller-advertises-motion-but-sends-zeroes)).
  No public API reaches the sensor then.
- **No `GCMotion` at all** — as on the Mac. Reading the sensor on iOS would mean claiming a
  Bluetooth HID device that the system's own HID service holds and sending it the console's
  EnableIMU handshake; that is private IOKit, and the entitlement problem is claiming the device,
  not calling the API.

In the last two cases, motion on an iPad comes from a **Joy-Con 2**, whose CoreBluetooth transport
is already shared by the Mac and iOS front ends (`pad_switch2_apple.m`, `DM_SW2`), or from the
iPad's own gyro (`DmGamepad.m`).
