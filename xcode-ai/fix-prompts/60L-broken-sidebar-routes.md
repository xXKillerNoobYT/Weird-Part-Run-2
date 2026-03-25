# 60L — Fix Broken Sidebar Routes

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Two sidebar routes are unreachable because IOSContentRouter.swift is missing their cases. The OrdersRouter already handles `"orders-parts"` and `"orders-wishlist"` tab IDs, and NavigationConfig already defines both tabs in the Orders module. The only thing missing is the IOSContentRouter path mapping.

Additionally, the People module in NavigationConfig is missing a `people-dashboard` tab even though `IOSPeopleDashboardPage` exists and `PeopleRouter` already handles the `"people-dashboard"` case.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Navigation/IOSContentRouter.swift` — see the Orders sub-routes section (around line 151-163)
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — see the People module (around line 163)

## Task

### Step 1: Add missing Orders routes to IOSContentRouter

In `IOSContentRouter.swift`, find the Orders sub-routes section. After the `"/orders/approvals"` case (line 163), add these two cases BEFORE the `// Fleet sub-routes` comment:

```swift
        case "/orders/parts":
            OrdersRouter(tabId: "orders-parts")
        case "/orders/wishlist":
            OrdersRouter(tabId: "orders-wishlist")
```

The final Orders block should look like:

```swift
        // Orders sub-routes
        case "/orders/jpos", "/orders/requests":
            OrdersRouter(tabId: "orders-jpos")
        case "/orders/purchase-orders":
            OrdersRouter(tabId: "orders-pos")
        case "/orders/returns":
            OrdersRouter(tabId: "orders-returns")
        case "/orders/procurement":
            OrdersRouter(tabId: "orders-procurement")
        case "/orders/staging", "/orders/unified-order":
            OrdersRouter(tabId: "orders-staging")
        case "/orders/approvals":
            OrdersRouter(tabId: "orders-approvals")
        case "/orders/parts":
            OrdersRouter(tabId: "orders-parts")
        case "/orders/wishlist":
            OrdersRouter(tabId: "orders-wishlist")
```

### Step 2: Add people-dashboard tab to NavigationConfig

In `NavigationConfig.swift`, find the People module definition (line 163). Add a Dashboard tab as the FIRST tab in the array:

```swift
    AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
        AppTab(id: "people-dashboard", label: "Dashboard", icon: "gauge.with.dots.needle.50percent", path: "/people/dashboard"),
        AppTab(id: "people-employees", label: "Employees", icon: "person.fill", path: "/people/employees", permission: "view_people"),
        // ... rest of existing tabs unchanged
    ], permission: "view_people"),
```

### Step 3: Verify People Dashboard route exists in IOSContentRouter

Check that IOSContentRouter already has a case for `"/people/dashboard"`. If it does NOT, add it in the People sub-routes section:

```swift
        case "/people/dashboard":
            PeopleRouter(tabId: "people-dashboard")
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Navigation/IOSContentRouter.swift` — add 2 missing Orders cases + verify People dashboard case
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — add `people-dashboard` tab to People module

## Success Criteria

- [ ] `/orders/parts` route resolves to `OrdersRouter(tabId: "orders-parts")` in IOSContentRouter
- [ ] `/orders/wishlist` route resolves to `OrdersRouter(tabId: "orders-wishlist")` in IOSContentRouter
- [ ] People module in NavigationConfig has a `people-dashboard` tab as its first entry
- [ ] `/people/dashboard` route exists in IOSContentRouter
- [ ] All routes match their corresponding Router tab IDs exactly
- [ ] Builds without errors
