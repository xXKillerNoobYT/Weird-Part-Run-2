import Foundation

/// All onboarding tasks organized by page ID.
/// Keys match tab IDs from NavigationConfig (e.g., "dashboard-home", "jobs-list").
let onboardingTaskRegistry: [String: [OnboardingTask]] = [

    // MARK: - Dashboard
    "dashboard-home": [
        OnboardingTask(id: "dashboard-view-kpis", title: "View Your Dashboard", description: "Look at the KPI cards showing your business overview.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "dashboard-tap-kpi", title: "Tap a KPI Card", description: "Tap any KPI card to see detailed information.", requiredPermission: nil, isRequired: false),
    ],
    "dashboard-clock": [
        OnboardingTask(id: "clock-in", title: "Clock In", description: "Clock in to the Shop or any active job to start tracking your time.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "clock-out", title: "Clock Out", description: "Clock out when you're done. Answer the questionnaire.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "clock-break", title: "Take a Break", description: "Try the Break or Lunch button to see how break tracking works.", requiredPermission: nil, isRequired: false),
    ],
    "dashboard-report": [
        OnboardingTask(id: "daily-report-view", title: "View a Daily Report", description: "See how the system auto-generates daily reports from clock and to-do data.", requiredPermission: nil, isRequired: true),
    ],
    "dashboard-scanner": [
        OnboardingTask(id: "scanner-open", title: "Open the QR Scanner", description: "Try scanning a QR code or typing a tool/part ID.", requiredPermission: nil, isRequired: false),
    ],

    // MARK: - Jobs
    "jobs-list": [
        OnboardingTask(id: "jobs-view-list", title: "Browse Jobs", description: "See all active and completed jobs. Tap the status cards to filter.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "jobs-create", title: "Create a Job", description: "Tap + to create a new job with name, customer, and priority.", requiredPermission: "manage_jobs", isRequired: true),
        OnboardingTask(id: "jobs-tap-detail", title: "View Job Detail", description: "Tap any job to see its full dashboard with hours, budget, and team.", requiredPermission: nil, isRequired: true),
    ],
    "jobs-labor": [
        OnboardingTask(id: "labor-view", title: "View Labor Hours", description: "See how hours are tracked per employee and per job.", requiredPermission: "view_labor", isRequired: true),
    ],
    "jobs-reports": [
        OnboardingTask(id: "job-reports-view", title: "View Job Reports", description: "See reports on job profitability and progress.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Chat
    "chat-channels": [
        OnboardingTask(id: "chat-view-channels", title: "View Channels", description: "See all your message channels — job chats, DMs, Q&A, and supplier messages.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "chat-send-message", title: "Send a Message", description: "Open any channel and send a test message.", requiredPermission: nil, isRequired: false),
    ],
    "chat-questions": [
        OnboardingTask(id: "qa-view", title: "View Q&A", description: "See how questions get routed up the chain of command.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Scheduling
    "scheduling-calendar": [
        OnboardingTask(id: "schedule-view", title: "View Calendar", description: "See the week/month schedule with job assignments.", requiredPermission: nil, isRequired: true),
    ],
    "scheduling-dispatch": [
        OnboardingTask(id: "dispatch-view", title: "View Dispatch Board", description: "See who's assigned where today.", requiredPermission: "manage_dispatch", isRequired: true),
    ],
    "scheduling-time-off": [
        OnboardingTask(id: "timeoff-view", title: "View Time Off", description: "See time-off requests and their approval status.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Warehouse
    "warehouse-dashboard": [
        OnboardingTask(id: "wh-dashboard-view", title: "View Warehouse Dashboard", description: "See today's movements, receiving activity, and audit status.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-movements": [
        OnboardingTask(id: "wh-movements-view", title: "View Movements", description: "See recent stock movements — transfers, receives, returns.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "wh-movement-start", title: "Start a Movement", description: "Tap + to start the Movement Wizard and move stock between locations.", requiredPermission: "manage_warehouse", isRequired: false),
    ],
    "warehouse-locations": [
        OnboardingTask(id: "wh-locations-view", title: "View Floor Plan", description: "See the warehouse layout with shelves, pipe racks, and storage units.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-staging": [
        OnboardingTask(id: "wh-staging-view", title: "View Staging Area", description: "See parts staged for jobs, organized into boxes.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-receiving": [
        OnboardingTask(id: "wh-receiving-view", title: "View Receiving", description: "See incoming shipments and start receiving sessions.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-audit": [
        OnboardingTask(id: "wh-audit-view", title: "View Audit Queue", description: "See which parts need counting based on confidence levels.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-inventory": [
        OnboardingTask(id: "wh-inventory-view", title: "Browse Inventory", description: "See all parts with stock levels at your location.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Orders
    "orders-pos": [
        OnboardingTask(id: "po-view-list", title: "View Purchase Orders", description: "See all POs — draft, ordered, partial, received.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "po-create", title: "Create a PO", description: "Tap + to start a new purchase order for a supplier.", requiredPermission: "manage_orders", isRequired: false),
    ],
    "orders-jpos": [
        OnboardingTask(id: "jpo-view-list", title: "View Job Orders", description: "See parts orders from job crews.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "jpo-create", title: "Create a JPO", description: "Use the cart builder to order parts for a job.", requiredPermission: nil, isRequired: true),
    ],
    "orders-procurement": [
        OnboardingTask(id: "procurement-view", title: "View Procurement", description: "See consolidated demand from JPOs, wishlist, and forecasts.", requiredPermission: "manage_orders", isRequired: true),
    ],
    "orders-returns": [
        OnboardingTask(id: "returns-view", title: "View Returns", description: "See returned parts and their status.", requiredPermission: nil, isRequired: true),
    ],
    "orders-wishlist": [
        OnboardingTask(id: "wishlist-view", title: "View Wishlist", description: "See suggested and requested parts for future orders.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Fleet
    "fleet-dashboard": [
        OnboardingTask(id: "fleet-dashboard-view", title: "View Fleet Dashboard", description: "See vehicle status, fuel costs, and maintenance due.", requiredPermission: nil, isRequired: true),
    ],
    "fleet-vehicles": [
        OnboardingTask(id: "fleet-vehicles-view", title: "View Vehicles", description: "See all company vehicles with status and assignments.", requiredPermission: nil, isRequired: true),
    ],
    "fleet-my-truck": [
        OnboardingTask(id: "fleet-my-truck", title: "View Your Vehicle", description: "See your assigned truck, parts, tools, and recent logs.", requiredPermission: nil, isRequired: true),
    ],
    "fleet-maintenance": [
        OnboardingTask(id: "fleet-maintenance-view", title: "View Maintenance", description: "See upcoming and overdue maintenance tasks.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Tools
    "tools-dashboard": [
        OnboardingTask(id: "tools-dashboard-view", title: "View Tools Dashboard", description: "See checked-out tools, maintenance due, and quick actions.", requiredPermission: nil, isRequired: true),
    ],
    "tools-registry": [
        OnboardingTask(id: "tools-browse", title: "Browse Tools", description: "See all company tools with status and location.", requiredPermission: nil, isRequired: true),
    ],
    "tools-checkouts": [
        OnboardingTask(id: "tools-checkouts-view", title: "View Checkouts", description: "See who has what tools checked out.", requiredPermission: nil, isRequired: true),
    ],
    "tools-kits": [
        OnboardingTask(id: "tools-kits-view", title: "View Tool Kits", description: "See tool kits and their contents.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Notebooks
    "notebooks-all": [
        OnboardingTask(id: "notebooks-view", title: "View Notebooks", description: "See job notebooks, general notes, and daily reports.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "notebooks-create", title: "Create a Notebook", description: "Tap + to create a new notebook for a job or general notes.", requiredPermission: nil, isRequired: false),
    ],
    "notebooks-job-notebooks": [
        OnboardingTask(id: "job-notebooks-view", title: "View Job Notebooks", description: "See notebooks linked to specific jobs.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Parts
    "parts-catalog": [
        OnboardingTask(id: "catalog-search", title: "Search for a Part", description: "Type a part name in the search bar.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "catalog-filter", title: "Use Filters", description: "Tap the filter chips to narrow by category, brand, or type.", requiredPermission: nil, isRequired: false),
        OnboardingTask(id: "catalog-detail", title: "View Part Detail", description: "Tap a part to see its full info — stock, pricing, history, location.", requiredPermission: nil, isRequired: true),
    ],
    "parts-categories": [
        OnboardingTask(id: "categories-browse", title: "Browse the Hierarchy", description: "Expand the tree to see Category → Style → Type → Brand → Color.", requiredPermission: nil, isRequired: true),
    ],
    "parts-brands": [
        OnboardingTask(id: "brands-view", title: "View Brands", description: "See all brands and their linked suppliers.", requiredPermission: nil, isRequired: true),
    ],
    "parts-suppliers": [
        OnboardingTask(id: "suppliers-view", title: "View Suppliers", description: "See supplier scores and contact info.", requiredPermission: nil, isRequired: true),
    ],
    "parts-pricing": [
        OnboardingTask(id: "pricing-view", title: "View Pricing Tiers", description: "See how pricing cascades from category to individual part.", requiredPermission: "show_dollar_values", isRequired: true),
    ],
    "parts-companions": [
        OnboardingTask(id: "companions-view", title: "View Companion Rules", description: "See which parts are commonly used together.", requiredPermission: nil, isRequired: true),
    ],
    "parts-forecasting": [
        OnboardingTask(id: "forecast-view", title: "Check Forecasts", description: "See which parts are running low and what the system recommends.", requiredPermission: nil, isRequired: true),
    ],
    "parts-import-export": [
        OnboardingTask(id: "import-view", title: "View Import/Export", description: "See how to import parts from CSV or export your catalog.", requiredPermission: "manage_parts", isRequired: false),
    ],

    // MARK: - People
    "people-dashboard": [
        OnboardingTask(id: "people-dashboard-view", title: "View People Dashboard", description: "See team overview with headcount and certifications.", requiredPermission: nil, isRequired: true),
    ],
    "people-employees": [
        OnboardingTask(id: "people-view", title: "View Employees", description: "See your team, their hats, and contact info.", requiredPermission: nil, isRequired: true),
    ],
    "people-customers": [
        OnboardingTask(id: "customers-view", title: "View Customers", description: "See customer list with job history.", requiredPermission: nil, isRequired: true),
    ],
    "people-hats": [
        OnboardingTask(id: "hats-view", title: "View Hats & Permissions", description: "See how permissions work — hats control who can do what.", requiredPermission: "manage_people", isRequired: false),
    ],

    // MARK: - Office
    "office-dashboard": [
        OnboardingTask(id: "office-view", title: "View Office Dashboard", description: "See the daily briefing, attention items, and financial snapshot.", requiredPermission: officeAccessPermission, isRequired: true),
    ],
    "office-approvals": [
        OnboardingTask(id: "approvals-view", title: "View Approvals Queue", description: "See all pending approvals — JPOs, deletions, tool edits, time-off.", requiredPermission: officeAccessPermission, isRequired: true),
    ],

    // MARK: - Reports
    "reports-hub": [
        OnboardingTask(id: "reports-view", title: "View Reports", description: "See business reports: timesheets, spending, profitability, fleet.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Settings
    "settings-general": [
        OnboardingTask(id: "settings-theme", title: "Set Your Theme", description: "Choose light/dark mode and your preferred accent color.", requiredPermission: nil, isRequired: false),
    ],
]
