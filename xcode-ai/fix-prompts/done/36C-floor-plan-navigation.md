# 36C — Warehouse GPS Navigation + QR Scan Integration

> **Chain position:** 36A → 36B → **36C** → 36D
> **Prerequisite:** 36B (floor plan UI exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

### Directional Warehouse GPS
When a user scans any sticker/QR or searches for a part:
- System knows the user's current position (from last scan)
- Shows directional guidance: "Go RIGHT 9 rows, Unit 5, Shelf 2, Area 4"
- [Show on Floor Plan] highlights the path from current to target
- Works with the floor plan from 36B

### QR Scan → Full Location View
Scanning any location QR (row, unit, shelf, or area) shows:
- What's at that location (parts, tools, kits)
- What SHOULD be here but is checked out (who has it, where)
- Empty spots where kits/tools belong
- Part confidence indicators
- [Quick Audit] [Assign Part] [Navigate Elsewhere]

### Navigation Service Methods
Add to WarehouseService:
- `getDirections(fromAreaId:toAreaId:)` → DirectionResult (row diff, unit diff, text instructions)
- `setUserCurrentPosition(userId:areaId:)` → updates last known position
- `getLocationByQR(qrCode:)` → LocationInfo (type, id, contents)

## Success Criteria
- [ ] Scan any QR → full location contents with checked-out items
- [ ] Directional text: "Go RIGHT X rows, Unit Y"
- [ ] Floor plan highlights path when navigating
- [ ] User position tracked from last scan
- [ ] Project builds with no errors
