# Login at iPhone 13 mini × AX5 — Keyboard Overlap Fix

> Owner: UXDesigner (design). Implementer: iOS engineer. Tracking: Paperclip WEI-1084 / GitHub PR #432.
> Related, sibling fix already shipped on iPhone 13 mini at **default** Dynamic Type: Paperclip WEI-1052 → GitHub #408 (closed 2026-05-13).

## 1. Problem (verified)

- **Device:** iPhone 13 mini simulator, iOS 26.4.1, 375 × 812 pt.
- **Setting:** Dynamic Type **AX5** (`accessibility-extra-extra-extra-large`), set via `xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`.
- **Path:** Launch app → select seeded `UITest Owner` → focus PIN field (numberPad keyboard opens).
- **Observed (WEI-1062 capture):** number pad begins at ≈ y=512; `Sign In` button frame is y=515–592. Sign In is fully overlapped by the pad. No scroll, no keyboard-aware reposition, no dismiss affordance — at AX5 the user has no obvious way to reach Sign In.
- The existing WEI-1052 fix solves the default-Dynamic-Type case (Sign In moves up just enough to be tappable) but does not survive AX text scaling because the header and PIN form together exceed the available 320 pt that remains above the number pad on a 375 × 812 screen.

## 2. Why the current layout fails at AX5

The pre-fix selected-user branch in `Weird Parts IOS/Weird Parts IOS/Auth/LoginView.swift` was an outer `VStack` with:

1. A decorative header (`padding(.top, 40)`, 48pt wrench icon, `largeTitle` "WiredPart", subheadline copy, `padding(.bottom, 24)`).
2. The selected-user PIN form (Back button row, `Hello, <name>` title2, `SecureField` with `frame(maxWidth: 200)`, error caption, prominent `Sign In` button).
3. A trailing `Spacer()` that pins everything to the top.

At AX5 the header alone is ≈ 280–340 pt (largeTitle line-height roughly 3× default, subheadline wraps to 2–3 lines). The form adds another ≈ 250–300 pt. There is no `ScrollView`, no `.safeAreaInset(edge: .bottom)`, no `dynamicTypeSize` adaption, no keyboard toolbar, and the `SecureField` width is hard-clamped to 200 pt which truncates the AX placeholder.

When the number pad opens (≈ 242 pt tall, top edge y ≈ 512 on iPhone 13 mini), `Sign In` is below that line and unreachable.

## 3. Design fix (build-ready)

Apply the four changes below together. Each addresses a distinct failure mode; shipping only a subset will leave AX5 partially broken.

### 3.1 Dock Sign In above the keyboard via `safeAreaInset(edge: .bottom)`

Move the Sign In button (and the inline error message, when present) out of the main content VStack and into a `.safeAreaInset(edge: .bottom)` modifier on the root view. iOS automatically extends bottom safe area to the keyboard top, so the inset block floats above the number pad with **no manual offset math**.

```swift
.safeAreaInset(edge: .bottom) {
    if selectedUser != nil {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("loginErrorMessage")
            }
            Button(action: attemptLogin) {
                Group {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pin.count < 4 || isLoading)
            .accessibilityIdentifier("loginSignInButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar) // visual separation when content scrolls under
    }
}
```

Rationale: this is the single highest-impact change. Sign In becomes reachable at any Dynamic Type size, on any iPhone, with no JS-style keyboard math. Full-width (`maxWidth: .infinity`) ensures the AX5 label has room to wrap before truncating.

### 3.2 Wrap the PIN entry section in a `ScrollView` with interactive dismissal

The selected-user form must scroll on its own when content exceeds the available space above the keyboard. Wrap the PIN form branch in:

```swift
ScrollView {
    VStack(spacing: 16) { /* existing PIN form */ }
        .padding()
        .frame(maxWidth: .infinity)
}
.scrollDismissesKeyboard(.interactively)
```

- `.interactively` lets the user drag down to dismiss the pad, which is the cheapest recovery affordance on a `numberPad` keyboard (no return key).
- The header can stay above the ScrollView OR move inside it — see 3.3.

### 3.3 Collapse the decorative header at accessibility sizes

Add an `@Environment(\.dynamicTypeSize)` read and collapse the header at AX sizes. The icon and tagline are decorative; once the user has selected a name, they don't need a brand block consuming 60% of the visible area.

```swift
@Environment(\.dynamicTypeSize) private var typeSize

private var isAccessibilitySize: Bool {
    typeSize >= .accessibility1
}

// In body:
if !(selectedUser != nil && isAccessibilitySize) {
    VStack(spacing: 8) {
        Image(systemName: "wrench.and.screwdriver.fill")
            .decorativeIconFont(48)
            .foregroundStyle(Color.accentColor)
        Text("WiredPart").font(.largeTitle).fontWeight(.bold)
        Text("Select your name and enter your PIN")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .padding(.top, isAccessibilitySize ? 12 : 40)
    .padding(.bottom, isAccessibilitySize ? 12 : 24)
    .padding(.horizontal)
}
```

When the PIN screen is active at AX5, the header collapses entirely, freeing ~250 pt for the form to breathe.

### 3.4 Add a `Done` keyboard toolbar + remove the 200 pt PIN-field clamp

Number pads have no return key. Add a toolbar so AX users (who may not know about the swipe-down gesture) can always dismiss:

```swift
SecureField("Enter PIN", text: $pin)
    .textContentType(.password)
    .keyboardType(.numberPad)
    .textFieldStyle(.roundedBorder)
    .frame(maxWidth: 320)         // was 200 — too narrow at AX5
    .multilineTextAlignment(.center)
    .focused($pinFocused)
    .onSubmit { attemptLogin() }
    .accessibilityIdentifier("loginPINField")
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { pinFocused = false }
                .accessibilityIdentifier("loginPINDoneButton")
        }
    }
```

Add `@FocusState private var pinFocused: Bool` to the view, and `.onChange(of: selectedUser) { _, new in pinFocused = new != nil }` so the field auto-focuses when a user is selected (preserving current "tap user → type PIN" flow).

## 4. Acceptance criteria (for engineering verification)

The fix is complete when **all** of the following pass on iPhone 13 mini (375 × 812) iOS 26.4.1:

1. Default Dynamic Type — Sign In tappable while number pad is visible (existing #408 behavior preserved).
2. AX5 (`accessibility-extra-extra-extra-large`) — Sign In tappable while number pad is visible. `XCUIElement.isHittable` returns `true` for `loginSignInButton`.
3. AX5 — PIN field placeholder is not truncated.
4. Number pad shows a `Done` toolbar that dismisses the keyboard, restoring the full layout.
5. Drag-down on the PIN form interactively dismisses the keyboard.
6. Back chevron (`loginBackButton`) is tappable at AX5 (must not be pushed behind the keyboard either — verify when AX header collapse is active, Back stays at the top of the scroll content).
7. Inline error message (`loginErrorMessage`) is visible above the Sign In dock when login fails.
8. iPad mini regression check — user-list landing layout unchanged.
9. UITest seed flow (`UITest Owner` / `1234`) reaches the post-login banner without the auto-login workaround.

Tap-target requirement: Sign In and Done must each be ≥ 44 × 44 pt at every Dynamic Type size.

## 5. Out of scope (do NOT change in this fix)

- The user-list landing layout (already verified clean at AX5 in WEI-1052 QA on default DT; no AX-specific complaint on file).
- The PIN hashing / auth pipeline.
- Visual identity (icon, brand color). Collapse is conditional on AX size + PIN screen active only.
- Forgot PIN flow — separate page, no overlap risk.

## 6. Handoff

- Engineering issue: WEI-1084 tracks the AX5 login keyboard-overlap fix and should link this plan.
- QA: re-run the AX5 login capture after the fix lands, plus a new AX5 result-bundle capture under `docs/testing/artifacts/wei-1084/`.
- Mark WEI-1084 done once the verification matrix in §4 is green.
