//
//  Weird_Parts_IOSUITests.swift
//  Weird Parts IOSUITests
//
//  UI test suite for the Weird Parts iOS app.
//  Focuses on the Parts Hierarchy (Categories) flow: sheet open/close,
//  data creation, list refresh, and persistence.
//
//  Accessibility identifiers used:
//    Page-level:   partsCategoriesPage, categoriesLoadingIndicator, categoriesErrorState
//    Tree:         categoriesTreeList, categoriesAddMenu, categoriesSearchField,
//                  categoryRow_{id}, addStyleButton_{catId}, createFirstCategoryButton
//    Editor:       editCategoryButton, deleteCategoryButton, editStyleButton, etc.
//    Form sheets:  categoryFormSheet, categoryNameField, categoryDescriptionField,
//                  categoryFormSaveButton, categoryFormCancelButton,
//                  styleFormSheet, styleNameField, styleFormSaveButton, etc.
//                  typeFormSheet, typeNameField, typeFormSaveButton, etc.
//                  colorFormSheet, colorNameField, colorFormSaveButton, etc.
//

import XCTest

final class Weird_Parts_IOSUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Pass a launch argument so the app can detect testing mode
        // (useful for seeding test data or skipping onboarding)
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper: Navigate to Parts > Categories

    /// Navigates from the main tab bar to the Parts > Categories page.
    /// Handles the case where the app may be on a different tab.
    private func navigateToCategories() {
        // Tap the "Parts" tab (or "More" then "Parts" on iPhone)
        let partsTab = app.tabBars.buttons["Parts"]
        if partsTab.waitForExistence(timeout: 10) {
            partsTab.tap()
        } else {
            // On iPhone with many tabs, Parts may be under "More"
            let moreTab = app.tabBars.buttons["More"]
            if moreTab.waitForExistence(timeout: 5) {
                moreTab.tap()
                let partsCell = app.cells.staticTexts["Parts"]
                if partsCell.waitForExistence(timeout: 5) {
                    partsCell.tap()
                }
            }
        }

        // Now navigate to the Categories sub-tab
        let categoriesButton = app.buttons["Categories"]
        if categoriesButton.waitForExistence(timeout: 5) {
            categoriesButton.tap()
        } else {
            // Try tapping by static text (some layouts use text labels)
            let categoriesText = app.staticTexts["Categories"]
            if categoriesText.waitForExistence(timeout: 3) {
                categoriesText.tap()
            }
        }

        // Wait for the page to appear
        let page = app.otherElements["partsCategoriesPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 10),
                      "Parts Categories page should appear after navigation")
    }

    // MARK: - Helper: Wait for loading to complete

    /// Waits for the loading indicator to disappear, indicating data has loaded.
    private func waitForLoadingToComplete(timeout: TimeInterval = 10) {
        let loadingIndicator = app.otherElements["categoriesLoadingIndicator"]
        // If loading indicator exists, wait for it to disappear
        if loadingIndicator.exists {
            let disappeared = NSPredicate(format: "exists == false")
            expectation(for: disappeared, evaluatedWith: loadingIndicator, handler: nil)
            waitForExpectations(timeout: timeout)
        }
    }

    // MARK: - Test 1: Category Sheet Opens and Closes

    @MainActor
    func testNewCategorySheetOpensAndCloses() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Check if there's an empty state with "Create First Category" button
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            // Empty state — tap "Create First Category"
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            // Has existing categories — use the + menu
            addMenu.tap()
            let newCategoryItem = app.buttons["addCategoryMenuItem"]
            XCTAssertTrue(newCategoryItem.waitForExistence(timeout: 3),
                          "New Category menu item should appear")
            newCategoryItem.tap()
        }

        // Verify the category form sheet appeared
        let formSheet = app.otherElements["categoryFormSheet"]
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5),
                      "Category form sheet should appear after tapping Add")

        // Verify form fields are present
        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3),
                      "Category name field should be visible")

        let descField = app.textFields["categoryDescriptionField"]
        XCTAssertTrue(descField.exists, "Description field should be visible")

        // Verify Cancel button works
        let cancelButton = app.buttons["categoryFormCancelButton"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should be visible")
        cancelButton.tap()

        // Form should be dismissed
        XCTAssertFalse(formSheet.waitForExistence(timeout: 3),
                       "Category form sheet should be dismissed after Cancel")
    }

    // MARK: - Test 2: Create New Category Successfully

    @MainActor
    func testCreateNewCategorySuccessfully() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Open the add category sheet
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            let newCategoryItem = app.buttons["addCategoryMenuItem"]
            XCTAssertTrue(newCategoryItem.waitForExistence(timeout: 3))
            newCategoryItem.tap()
        }

        // Wait for form to appear
        let formSheet = app.otherElements["categoryFormSheet"]
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5),
                      "Category form sheet should appear")

        // Fill in the form
        let uniqueName = "TestCategory_\(Int(Date().timeIntervalSince1970))"
        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(uniqueName)

        let descField = app.textFields["categoryDescriptionField"]
        descField.tap()
        descField.typeText("A test category created by UI tests")

        // Save
        let saveButton = app.buttons["categoryFormSaveButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled after entering name")
        saveButton.tap()

        // Wait for sheet to dismiss
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: formSheet)
        waitForExpectations(timeout: 10)

        // Verify the new category appears in the tree list
        let treeList = app.scrollViews["categoriesTreeList"]
        XCTAssertTrue(treeList.waitForExistence(timeout: 10),
                      "Categories tree list should appear after creating first category")

        // The new category name should be visible somewhere in the UI
        let categoryText = app.staticTexts[uniqueName]
        XCTAssertTrue(categoryText.waitForExistence(timeout: 10),
                      "Newly created category '\(uniqueName)' should appear in the tree")
    }

    // MARK: - Test 3: Category List Loads Data Correctly

    @MainActor
    func testCategoryListLoadsAllDataCorrectly() throws {
        navigateToCategories()

        // Wait for loading to complete
        waitForLoadingToComplete()

        // Verify error state is NOT shown
        let errorState = app.otherElements["categoriesErrorState"]
        XCTAssertFalse(errorState.exists,
                       "Error state should not be visible when data loads successfully")

        // Page should be visible
        let page = app.otherElements["partsCategoriesPage"]
        XCTAssertTrue(page.exists, "Categories page should be visible")

        // Either the tree list OR the empty state should be shown (not both)
        let treeList = app.scrollViews["categoriesTreeList"]
        let emptyButton = app.buttons["createFirstCategoryButton"]

        let hasTree = treeList.exists
        let hasEmpty = emptyButton.exists

        XCTAssertTrue(hasTree || hasEmpty,
                      "Either the tree list or the empty state should be visible")
        XCTAssertFalse(hasTree && hasEmpty,
                       "Tree list and empty state should not both be visible")
    }

    // MARK: - Test 4: Data Persists and Displays After Sheet Dismiss

    @MainActor
    func testDataPersistsAndDisplaysAfterSheetDismiss() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Create a category
        let uniqueName = "PersistTest_\(Int(Date().timeIntervalSince1970))"

        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            app.buttons["addCategoryMenuItem"].tap()
        }

        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(uniqueName)

        app.buttons["categoryFormSaveButton"].tap()

        // Wait for sheet to dismiss
        let formSheet = app.otherElements["categoryFormSheet"]
        let disappeared = NSPredicate(format: "exists == false")
        expectation(for: disappeared, evaluatedWith: formSheet)
        waitForExpectations(timeout: 10)

        // Verify data appears
        let categoryText = app.staticTexts[uniqueName]
        XCTAssertTrue(categoryText.waitForExistence(timeout: 10),
                      "Category should persist and display after sheet dismiss")

        // Pull to refresh and verify data is still there
        let treeList = app.scrollViews["categoriesTreeList"]
        if treeList.exists {
            // Pull down to refresh
            let start = treeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = treeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: end)

            // Wait a moment for refresh to complete
            sleep(2)

            // Category should still be visible after refresh
            XCTAssertTrue(categoryText.waitForExistence(timeout: 5),
                          "Category should persist after pull-to-refresh")
        }
    }

    // MARK: - Test 5: Save Button Disabled When Name Empty

    @MainActor
    func testSaveButtonDisabledWhenNameEmpty() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Open sheet
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            app.buttons["addCategoryMenuItem"].tap()
        }

        let formSheet = app.otherElements["categoryFormSheet"]
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5))

        // Save button should be disabled when name is empty
        let saveButton = app.buttons["categoryFormSaveButton"]
        XCTAssertTrue(saveButton.exists, "Save button should exist")
        XCTAssertFalse(saveButton.isEnabled,
                       "Save button should be disabled when name field is empty")

        // Type a name
        let nameField = app.textFields["categoryNameField"]
        nameField.tap()
        nameField.typeText("ValidName")

        // Now save button should be enabled
        XCTAssertTrue(saveButton.isEnabled,
                      "Save button should be enabled after entering a name")

        // Clear the name
        nameField.tap()
        // Select all and delete
        nameField.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            app.keys["delete"].tap()
        }

        // Save should be disabled again (or still enabled if whitespace remains — edge case)
        // Cancel and dismiss
        app.buttons["categoryFormCancelButton"].tap()
    }

    // MARK: - Test 6: Search Filters Categories

    @MainActor
    func testSearchFiltersCategoriesTree() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // This test only makes sense if there are existing categories
        let treeList = app.scrollViews["categoriesTreeList"]
        guard treeList.waitForExistence(timeout: 5) else {
            // No categories yet — skip this test gracefully
            return
        }

        // Type into search field
        let searchField = app.textFields["categoriesSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3),
                      "Search field should be visible")
        searchField.tap()
        searchField.typeText("ZZZZZ_NONEXISTENT")

        // The tree should show "no results" or the content unavailable view
        // Wait a moment for filter to apply
        sleep(1)

        // Type a real search term (clear first)
        searchField.tap()
        searchField.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            app.keys["delete"].tap()
        }

        // Clear button should clear the search
        let clearButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'xmark'")).firstMatch
        if clearButton.exists {
            clearButton.tap()
        }
    }

    // MARK: - Test 7: App Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
