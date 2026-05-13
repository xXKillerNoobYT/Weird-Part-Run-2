# WEI-1029 QA Evidence Classification

Date: 2026-05-13
Agent: UIVerifier

## Published in This Slice

Published the human-readable QA reports plus the smallest material screenshot/hierarchy evidence needed to support them:

- `docs/testing/wei-996-new-parts-order-sourcing-modes-2026-05-13.md`
- `docs/testing/artifacts/wei-996/iphone-attachments/`
- `docs/testing/artifacts/wei-996/ipad-attachments/`
- `docs/testing/wei-1016-notebook-sidebar-layout-qa-2026-05-13.md`
- `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/51B9DF4D-D93E-41E4-A0AB-B340F9896AD7.png`
- `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/BC762C09-77CA-4B7D-92B7-F5C68DC4E27D.txt`
- `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/manifest.json`
- `docs/testing/wei-1020-settings-dirty-discard-rerun-2026-05-13.md`
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-attachments/435945C2-A5C1-47BE-ADDA-9CF996DE418B.png`
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-attachments/manifest.json`
- `docs/testing/wei-1022-settings-dirty-discard-rerun-2026-05-13.md`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/23DC0312-E457-435C-B2F5-BAFBB1163C5A.png`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/5BE7814B-3C68-4D7D-A873-66BD19ADE6BB.png`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/manifest.json`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-attachments/`

## Excluded Generated or Oversized Artifacts

The following local artifact groups are intentionally not published in this PR because they are generated Xcode result bundles or bulky raw attachment exports. The QA reports above preserve commands, pass/fail calls, and the exact local paths for forensic reruns.

- `docs/evidence/WEI-850/` (60 MB): generated `.xcresult` evidence bundle group without a separate human report in this slice.
- `docs/testing/artifacts/wei-996/ipad-sourcing-modes-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-996/iphone-sourcing-modes-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun2-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun3-debug-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-rerun4-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-compact-notebook-layout-target-rerun-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone17pro-compact-notebook-layout-2026-05-13.xcresult`
- `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/` files other than the manifest, key screenshot, and key accessibility tree listed above.
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-forecast-audit-temp.xcresult`
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-iphone17pro.xcresult`
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-project-iphone17pro.xcresult`
- `docs/testing/artifacts/wei-1020/settings-dirty-guards-attachments/` files other than the manifest and key confirmation screenshot listed above, including `35EF461C-DF90-41AA-B58A-3C75E7B3F38A.mp4`.
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-forecast-audit-iphone17pro.xcresult`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-iphone17pro.xcresult`
- `docs/testing/artifacts/wei-1022/settings-dirty-guards-attachments/` files other than the manifest and two key screenshots listed above, including `B4412C87-2D55-448D-A031-A4139E4B8D63.mp4`.

## Residual Follow-Up

- Keep local `.xcresult` bundles available only in the shared workspace unless a reviewer explicitly requests a zipped raw archive for a specific QA ticket.
- If another evidence PR is needed, the next coherent slice should use the same pattern: publish markdown reports and selected screenshots/manifests, exclude raw `.xcresult` directories by exact path.
