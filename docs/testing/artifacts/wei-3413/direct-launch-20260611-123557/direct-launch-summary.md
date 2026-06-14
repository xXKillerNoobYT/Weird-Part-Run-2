# WEI-3413 direct simctl launch check

Log: docs/testing/artifacts/wei-3413/direct-launch-20260611-123557/logs/direct-boot-install-launch.log

```text
Device before:
== Devices ==
-- iOS 26.3 --
-- iOS 26.4 --
-- iOS 26.4 --
-- iOS 26.5 --
    iPhone 17 Pro (81B76C8A-9A4F-46CE-8A89-ED1DC5842F43) (Shutdown) 
-- watchOS 26.2 --
-- watchOS 26.4 --
-- watchOS 26.5 --
Booting...
Monitoring boot status for iPhone 17 Pro (81B76C8A-9A4F-46CE-8A89-ED1DC5842F43).
[2026-06-11 18:35:59 +0000] Status=2, isTerminal=NO, Elapsed=00:01.
	Waiting on Data Migration
		Reason:(null)
		Migration Elapsed:00:00 seconds

[2026-06-11 18:35:59 +0000] Status=4, isTerminal=NO, Elapsed=00:01.
	Waiting on System App

[2026-06-11 18:36:00 +0000] Status=4, isTerminal=NO, Elapsed=00:02.
	Waiting on System App

[2026-06-11 18:36:02 +0000] Status=4294967295, isTerminal=YES, Elapsed=00:04.
	Finished

Installing app: /Users/IA/Library/Developer/Xcode/DerivedData/Weird_Parts-armqnibdcsefjqcnwnfnbspktuky/Build/Products/Debug-iphonesimulator/Weird Parts.app
Launching app...
weirdtoo.Weird-Parts-IOS: 40676
Device after:
== Devices ==
-- iOS 26.3 --
-- iOS 26.4 --
-- iOS 26.4 --
-- iOS 26.5 --
    iPhone 17 Pro (81B76C8A-9A4F-46CE-8A89-ED1DC5842F43) (Booted) 
-- watchOS 26.2 --
-- watchOS 26.4 --
-- watchOS 26.5 --

```
