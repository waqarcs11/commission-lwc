# Representative Commission System — Full Documentation

## Table of Contents
1. [Business Overview](#1-business-overview)
2. [Architecture Summary](#2-architecture-summary)
3. [Salesforce Org Setup](#3-salesforce-org-setup)
4. [Data Model](#4-data-model)
5. [Commission Plans & Tiers](#5-commission-plans--tiers)
6. [Apex Backend](#6-apex-backend)
7. [Lightning Web Components](#7-lightning-web-components)
8. [Permission Set & Security](#8-permission-set--security)
9. [Page Layout & Lightning Pages](#9-page-layout--lightning-pages)
10. [How It All Works Together](#10-how-it-all-works-together)
11. [Deployment Guide](#11-deployment-guide)

---

## 1. Business Overview

This system automates **sales representative commission calculations** inside Salesforce. It replaces a manual spreadsheet process and provides:

- A configurable admin screen where an administrator selects which data fields apply to each commission plan
- A commission entry screen where a manager/admin enters source data for a rep for a given month
- Automatic calculation of all commission components the moment data is saved
- A clean record detail view showing only the relevant fields for the active plan

**Five commission plans** are supported, each with different calculation logic and data entry requirements:

| Plan | Description |
|------|-------------|
| `Assistant_Renewals_Director_Comp` | Flat dollar tier payout based on funded/eligible unit attainment |
| `Brokered_CRR_Comp` | Flat dollar tier payout based on attainment |
| `Brokered_PM_Comp` | Percentage of base commission driven by tier attainment |
| `Cardiff_PM_Comp` | Cardiff deal margin commission plus tier payout |
| `Proposed_Comp` | Approve-to-fund ratio driven, includes $50K bonuses |

---

## 2. Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                        ADMIN SETUP                              │
│  Commission_Plan__mdt  +  Commission_Tier__mdt                  │
│  (plans & tier ranges stored as Custom Metadata)                │
│                              │                                  │
│                              ▼                                  │
│         commissionPlanAdmin LWC  (Admin Config Screen)          │
│         → saves field selections to Commission_Plan_Field_Config__c │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA ENTRY                                │
│  commissionEntry LWC  (Commission Entry Screen)                 │
│  → reads Commission_Plan_Field_Config__c to show only           │
│    the relevant fields for the selected plan                    │
│  → saves/updates Representative_Commission__c record            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AUTO-CALCULATION                            │
│  RepCommissionTrigger  (before insert / before update)          │
│  → calls CommissionCalculationService                           │
│  → reads tiers from Commission_Tier__mdt                        │
│  → writes all 14 calc fields directly onto the record           │
│  → if plan changed, clears old data entry fields                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RECORD DETAIL VIEW                         │
│  repCommissionRecord LWC  (Record Page)                         │
│  → reads the record's plan from Commission_Plan_Developer_Name__c │
│  → shows only configured data entry fields                      │
│  → shows all 14 calc results (read-only)                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Salesforce Org Setup

- **Org type:** Developer Edition (Trailblazer)
- **Org alias:** `MyCommissionOrg`
- **Username:** `adsknock@resourceful-shark-v02x54.com`
- **API Version:** 64.0
- **Project type:** Salesforce DX (source-tracked)
- **Deployment tool:** Salesforce CLI (`sf project deploy start`)

---

## 4. Data Model

### 4.1 Representative_Commission__c (Custom Object)

The single central object. Every record represents **one rep's commission for one month under one plan**.

#### System / Tracking Fields
| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Commission Plan | `Commission_Plan_Developer_Name__c` | Text | Stores the DeveloperName of the selected plan |
| Commission Month | `Commission_Month__c` | Date | The month this record covers |
| Commission Month Year | `Commission_Month_Year__c` | Text | Human-readable month label |
| Status | `Status__c` | Picklist | Draft → Calculated → Approved → Locked |

#### Data Entry Fields (input — configured per plan)
| Field Label | API Name | Type |
|---|---|---|
| Eligible Units | `Eligible_Units__c` | Number |
| Funded Units | `Funded_Units__c` | Number |
| Base Commission | `Base_Commission__c` | Currency |
| Brokered Margin % | `Brokered_Margin__c` | Percent |
| Brokered Margin ($) | `Brokered_Margin_Amount__c` | Currency |
| Team Closing Ratio | `Team_Closing_Ratio__c` | Percent |
| Team Margin % | `Team_Margin__c` | Percent |
| Team Margin ($) | `Team_Margin_Amount__c` | Currency |
| Termed Deal Margin % | `Termed_Deal_Margin_Percentage__c` | Percent |
| Termed Deal Margin ($) | `Termed_Deal_Margin_Amount__c` | Currency |
| Cardiff Deal Margin % | `Cardiff_Deal_Margin__c` | Percent |
| Cardiff Deal Margin ($) | `Cardiff_Deal_Margin_Amount__c` | Currency |
| 60 Day+ Termed Margin % | `Day60_Plus_Termed_Margin__c` | Percent |
| 60 Day+ Termed Margin ($) | `Day60_Plus_Termed_Margin_Amount__c` | Currency |
| Approve to Fund Ratio | `Approve_to_Fund_Ratio__c` | Percent |
| Proposed Comp Margin | `Proposed_Comp_Margin__c` | Currency |
| $50K Funded | `X50K_Funded__c` | Currency |
| $50K+ Funded | `X50KPlus_Funded__c` | Currency |
| Commission Adjustment | `Commission_Adjustment__c` | Currency |
| Commission Adjustment Note | `Commission_Adjustment_Note__c` | Text |

#### Calculation Output Fields (written by Apex — `_Calc__c` suffix)
The `_Calc__c` suffix is a convention that automatically excludes these from the admin config screen. Any field ending in `_calc__c` is treated as a system output, not a user input.

| Field Label | API Name | Type |
|---|---|---|
| Attainment | `Attainment_Calc__c` | Percent |
| Tier Lower | `Tier_Lower_Calc__c` | Number |
| Tier Upper | `Tier_Upper_Calc__c` | Number |
| Tier Payout | `Tier_Payout_Calc__c` | Number |
| Brokered Commission | `Brokered_Commission_Calc__c` | Currency |
| Team Closing Ratio Commission | `Team_Closing_Ratio_Commission_Calc__c` | Currency |
| Team Margin Commission | `Team_Margin_Commission_Calc__c` | Currency |
| Deal Margin Commission | `Deal_Margin_Commission_Calc__c` | Currency |
| Termed Deal Commission | `Termed_Deal_Commission_Calc__c` | Currency |
| Cardiff Commission | `Cardiff_Commission_Calc__c` | Currency |
| 60 Day Termed Commission | `Day60_Termed_Commission_Calc__c` | Currency |
| Proposed Comp Commission | `Proposed_Comp_Commission_Calc__c` | Currency |
| Commission Amount | `Commission_Amount_Calc__c` | Currency |
| Final Commission | `Final_Commission_Calc__c` | Currency |

---

### 4.2 Commission_Plan__mdt (Custom Metadata Type)

Stores the definition of each commission plan. Custom Metadata is used because plan definitions are configuration, not transactional data — they deploy with the package and don't require DML.

| Field | API Name | Type |
|---|---|---|
| Plan Name | `Label` | Text (standard) |
| Developer Name | `DeveloperName` | Text (standard) |
| Payout Type | `Payout_Type__c` | Picklist: Percent / Amount / Dollar / Currency |

**5 plan records deployed:**
- `Assistant_Renewals_Director_Comp`
- `Brokered_CRR_Comp`
- `Brokered_PM_Comp`
- `Cardiff_PM_Comp`
- `Proposed_Comp`

---

### 4.3 Commission_Tier__mdt (Custom Metadata Type)

Stores the tier ranges and payout values for each plan. Each tier record defines a band: if attainment falls between Lower and Upper, that tier's payout applies.

| Field | API Name | Type |
|---|---|---|
| Commission Plan | `Commission_Plan__c` | Text (DeveloperName of parent plan) |
| Tier Lower | `Lowest_of_Funded_Unit_Against_Eligible__c` | Number |
| Tier Upper | `Upper_of_Funded_Units_Against_Eligible__c` | Number |
| Tier Payout | `Plan_Tier_Payout__c` | Number |
| Payout Type | `Payout_Type__c` | Picklist |

**31 tier records** are deployed across all 5 plans, migrated from the legacy commission module.

---

### 4.4 Commission_Plan_Field_Config__c (Custom Object)

Stores which data entry fields are active for each commission plan. One record per plan-field combination.

| Field | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text | Auto-generated: `PlanName_FieldAPIName` |
| Commission Plan | `Commission_Plan_Developer_Name__c` | Text | Plan DeveloperName |
| Field API Name | `Field_API_Name__c` | Text | e.g. `Eligible_Units__c` |
| Object API Name | `Object_API_Name__c` | Text | Always `Representative_Commission__c` |

This table drives two things:
1. Which fields the **Commission Entry** screen shows when a plan is selected
2. Which fields the **Record Detail** LWC displays on the record page
3. Which fields are **cleared** when a user changes the plan on an existing record

---

## 5. Commission Plans & Tiers

### Calculation Logic Per Plan

#### Assistant_Renewals_Director_Comp
- **Attainment** = (Funded Units / Eligible Units) × 100
- **Deal Margin Commission** = flat dollar amount from tier (based on attainment %)
- **+ Termed Deal, Brokered, Team components** if applicable

#### Brokered_CRR_Comp
- **Attainment** = (Funded Units / Eligible Units) × 100
- **Deal Margin Commission** = flat dollar tier payout
- **+ Termed, Brokered, Team components**

#### Brokered_PM_Comp
- **Attainment** = (Funded Units / Eligible Units) × 100
- **Deal Margin Commission** = Base Commission × (Tier Payout % / 100)
- **+ Termed, Brokered, Team components**

#### Cardiff_PM_Comp
- **Attainment** = (Funded Units / Eligible Units) × 100
- **Cardiff Commission** = Cardiff Margin Amount × (Cardiff Margin % / 100) + Tier Payout
- **+ Termed, Team components**

#### Proposed_Comp
- **Attainment** = Approve-to-Fund Ratio (entered directly)
- **Proposed Commission** = Proposed Comp Margin × (Tier % / 100) + $50K Funded + $50K+ Funded

### Total Commission Formula (all plans)
```
Commission Amount = Brokered + Team Closing + Team Margin + Deal Margin
                  + Termed Deal + Cardiff + 60 Day Termed + Proposed Comp

Final Commission = Commission Amount + Commission Adjustment
```

---

## 6. Apex Backend

### 6.1 RepCommissionTrigger

**File:** `force-app/main/default/triggers/RepCommissionTrigger.trigger`

- Fires on **before insert** and **before update**
- Skips records with `Status__c = 'Locked'`
- Passes qualifying records to `CommissionCalculationService.process()`

Using `before` context means the Apex writes calculation results directly onto `Trigger.new` — no extra SOQL or DML needed.

---

### 6.2 CommissionCalculationService

**File:** `force-app/main/default/classes/CommissionCalculationService.cls`

The core calculation engine. Key responsibilities:

**Plan Change Detection**
When a record's `Commission_Plan_Developer_Name__c` changes on update:
- Queries `Commission_Plan_Field_Config__c` for the new plan
- Nulls out every data entry field that is NOT configured for the new plan
- Resets all `_Calc__c` fields to null
- Resets `Status__c` to `Draft`

This ensures stale data from the previous plan cannot corrupt the new plan's calculation.

**Tier Lookup**
- Queries `Commission_Tier__mdt` for all plans involved in the batch
- For each record, finds the tier where `Lower ≤ Attainment ≤ Upper`

**Calculation**
Runs per-plan logic and writes all 14 `_Calc__c` fields directly onto the record.

---

### 6.3 CommissionPlanAdminController

**File:** `force-app/main/default/classes/CommissionPlanAdminController.cls`

Used by the `commissionPlanAdmin` LWC (admin config screen).

| Method | Description |
|---|---|
| `getPlans()` | Returns all `Commission_Plan__mdt` records |
| `getAvailableFields()` | Returns all data-entry custom fields on `Representative_Commission__c`. Automatically excludes any field ending in `_calc__c` and 4 system fields |
| `getConfiguredFields(planDeveloperName)` | Returns field API names already saved for a plan |
| `saveConfig(planDeveloperName, fieldApiNames)` | Replaces all config records for the plan with the new selection |

**`_Calc__c` Auto-Exclusion:**
The admin screen uses `!apiName.endsWith('_calc__c')` to filter out calculation fields. This means any future calc field added with the `_Calc__c` suffix is automatically hidden from the config screen — no code changes required.

---

### 6.4 CommissionEntryController

**File:** `force-app/main/default/classes/CommissionEntryController.cls`

Used by the `commissionEntry` LWC (data entry screen).

| Method | Description |
|---|---|
| `getActiveUsers()` | Returns active Salesforce users for the rep picker |
| `getCommissionPlans()` | Returns all plans |
| `getFieldsForPlan(planDeveloperName)` | Returns field metadata (apiName, label, type) for configured fields |
| `getExistingRecord(userId, commissionDate, planDeveloperName)` | Checks if a record already exists for this rep/month/plan |
| `saveCommission(...)` | Creates or updates a `Representative_Commission__c` record |

---

## 7. Lightning Web Components

### 7.1 commissionPlanAdmin — Admin Config Screen

**Purpose:** Allows administrators to select which data entry fields are enabled for each commission plan.

**How it works:**
1. Admin selects a plan from the dropdown
2. All available data entry fields are shown as checkboxes
3. Admin checks the fields relevant to that plan
4. Clicks Save — field selections are stored in `Commission_Plan_Field_Config__c`

**Key design:** Fields with the `_Calc__c` suffix and system fields (`Status__c`, `Commission_Plan_Developer_Name__c`, etc.) are automatically excluded — the admin only sees actual data entry fields.

**Accessible via:** Navigation tab → **Commission Plan Field Config**

---

### 7.2 commissionEntry — Commission Entry Screen

**Purpose:** Multi-step form for creating or updating a commission record for a rep.

**Step 1 — Select context:**
- Pick the sales rep (user)
- Pick the month/year
- Pick the commission plan

**Step 2 — Enter data:**
- Only shows fields configured for the selected plan (reads `Commission_Plan_Field_Config__c`)
- If a record already exists for this rep/month/plan, pre-fills existing values
- Submit creates or updates the `Representative_Commission__c` record
- The before-trigger fires immediately and writes all calculated results

**Accessible via:** Navigation tab → **Commission Entry**

---

### 7.3 repCommissionRecord — Record Detail View

**Purpose:** Displays a `Representative_Commission__c` record with dynamic field visibility based on the plan.

**How it works:**
1. Reads `Commission_Plan_Developer_Name__c` from the current record using `@wire(getRecord)`
2. Calls `getConfiguredFields(planDeveloperName)` to get the field list for that plan
3. Renders three sections:
   - **Plan & Status** — always visible, read-only (plan name, status, month)
   - **Data Entry** — only the fields configured for this plan, editable
   - **Calculation Results** — all 14 `_Calc__c` fields, always read-only
4. Save Changes button submits the record edit form

**Used on:** `Representative_Commission__c` Lightning Record Page (set as Org Default)

---

## 8. Permission Set & Security

**Permission Set:** `Commission_Plan_Admin`

Grants access needed for the commission system to work. Assign to any user who needs access.

**Object Permissions:**
| Object | Create | Read | Edit | Delete |
|---|---|---|---|---|
| `Representative_Commission__c` | ✓ | ✓ | ✓ | ✓ |
| `Commission_Plan_Field_Config__c` | ✓ | ✓ | ✓ | ✓ |

**Apex Class Access:**
- `CommissionPlanAdminController`
- `CommissionEntryController`

**Field-Level Security:**
- Data entry fields: **Read + Edit**
- System/tracking fields: **Read + Edit**
- `_Calc__c` output fields: **Read only** (Apex writes these, users cannot)

**Why FLS matters:** The `getAvailableFields()` method checks `dfr.isAccessible()` before returning a field. Without explicit field permissions in the permission set, fields would be hidden from the admin config screen even if they exist on the object.

---

## 9. Page Layout & Lightning Pages

### 9.1 Representative Commission Layout (Page Layout)

**File:** `force-app/main/default/layouts/Representative_Commission__c-Representative Commission Layout.layout-meta.xml`

The standard Salesforce page layout used as a fallback. Contains all fields organized in three sections:
- **Plan & Status**
- **Data Entry** (all 20 data entry fields)
- **Calculation Results** (all 14 `_Calc__c` fields)

Note: This layout shows ALL fields. The dynamic per-plan filtering is handled by the `repCommissionRecord` LWC on the Lightning Record Page.

---

### 9.2 Commission Entry (Lightning App Page)

**File:** `force-app/main/default/flexipages/Commission_Entry.flexipage-meta.xml`

A full-screen App Page that hosts the `commissionEntry` LWC. Accessible from the navigation bar.

---

### 9.3 Commission Plan Field Config (Lightning App Page)

**File:** `force-app/main/default/flexipages/Commission_Plan_Field_Config.flexipage-meta.xml`

A full-screen App Page that hosts the `commissionPlanAdmin` LWC. Accessible from the navigation bar.

---

### 9.4 Representative Commission Record Page (Lightning Record Page)

**File:** `force-app/main/default/flexipages/Representative_Commission_Record_Page.flexipage-meta.xml`

A Record Page assigned as **Org Default** for `Representative_Commission__c`. It hosts the `repCommissionRecord` LWC, which provides dynamic field visibility based on the active plan.

**How it was set up:**
1. `repCommissionRecord` LWC was deployed with `lightning__RecordPage` as its target
2. Opened any `Representative_Commission__c` record
3. Clicked gear icon → Edit Page in Lightning App Builder
4. Dragged `repCommissionRecord` onto the main content area
5. Removed the standard Record Detail component
6. Saved → Activated → Set as Org Default

---

## 10. How It All Works Together

### End-to-End Flow: Creating a Commission Record

```
1. Admin (one-time setup)
   └── Opens Commission Plan Field Config screen
   └── Selects "Brokered_PM_Comp"
   └── Checks: Eligible Units, Funded Units, Base Commission,
              Termed Deal Margin %, Termed Deal Margin ($)
   └── Clicks Save
   └── Five Commission_Plan_Field_Config__c records are created

2. Manager enters data
   └── Opens Commission Entry screen
   └── Step 1: Selects Rep, Month (March 2026), Plan (Brokered_PM_Comp)
   └── Step 2: Only 5 configured fields are shown
   └── Enters: Eligible=500, Funded=450, Base Commission=$10,000
   └── Clicks Submit → Representative_Commission__c record is created

3. Salesforce trigger fires (before insert)
   └── RepCommissionTrigger calls CommissionCalculationService.process()
   └── Attainment = (450/500) × 100 = 90%
   └── Tier lookup: 90% falls in tier paying 12%
   └── Deal Margin Commission = $10,000 × 12% = $1,200
   └── Commission_Amount_Calc__c = $1,200
   └── Final_Commission_Calc__c = $1,200 + $0 adjustment = $1,200
   └── All calc fields written onto the record before it hits the database

4. Record is saved with full calculation results

5. Manager views the record
   └── repCommissionRecord LWC reads Commission_Plan_Developer_Name__c
   └── Queries Commission_Plan_Field_Config__c for Brokered_PM_Comp
   └── Shows only the 5 configured data entry fields (not all 20)
   └── Shows all 14 calc results below
```

### Plan Change Flow

```
Manager edits a record and changes the plan from Brokered_PM_Comp to Cardiff_PM_Comp

Before update trigger fires:
  └── Detects plan changed
  └── Loads configured fields for Cardiff_PM_Comp
  └── Clears any data entry fields NOT in Cardiff's config
      (e.g. Base_Commission__c is cleared because Cardiff doesn't use it)
  └── Resets all _Calc__c fields to null
  └── Resets Status to Draft
  └── Runs fresh calculation with Cardiff logic
  └── Record is saved with clean data for the new plan
```

---

## 11. Deployment Guide

### Prerequisites
- Salesforce CLI installed (`sf` command)
- Org authorized: `sf org login web --alias MyCommissionOrg`
- Working directory: `E:\xampp\htdocs\commission_LWC\rep-commission-lwc`

### Full Deploy Command
```bash
sf project deploy start --source-dir force-app --target-org MyCommissionOrg
```

### Deploy Individual Components
```bash
# Objects and fields
sf project deploy start --source-dir force-app/main/default/objects --target-org MyCommissionOrg

# Apex classes and trigger
sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/triggers --target-org MyCommissionOrg

# LWC components
sf project deploy start --source-dir force-app/main/default/lwc --target-org MyCommissionOrg

# Permission set
sf project deploy start --source-dir force-app/main/default/permissionsets --target-org MyCommissionOrg

# Custom metadata records (plans and tiers)
sf project deploy start --source-dir force-app/main/default/customMetadata --target-org MyCommissionOrg

# Page layout
sf project deploy start --source-dir force-app/main/default/layouts --target-org MyCommissionOrg
```

### Post-Deploy Steps (one-time manual)
1. **Assign permission set** to users who need access:
   Setup → Permission Sets → Commission Plan Admin Access → Manage Assignments

2. **Add navigation tabs** (if not already present):
   App Manager → Sales App → Edit → Navigation Items → add Commission Entry and Commission Plan Field Config

3. **Activate record page**:
   Open a Representative Commission record → gear icon → Edit Page → drag `repCommissionRecord` component → Save → Activate → Org Default

4. **Configure field mappings** for each plan:
   Navigate to Commission Plan Field Config tab → select each plan → check the relevant fields → Save

### Project File Structure
```
force-app/main/default/
├── classes/
│   ├── CommissionCalculationService.cls       ← Core calculation engine
│   ├── CommissionPlanAdminController.cls      ← Admin config Apex
│   └── CommissionEntryController.cls          ← Data entry Apex
├── triggers/
│   └── RepCommissionTrigger.trigger           ← Before insert/update
├── objects/
│   ├── Representative_Commission__c/          ← Main object + 38 fields
│   ├── Commission_Plan_Field_Config__c/       ← Field config object
│   ├── Commission_Plan__mdt/                  ← Plan metadata type
│   └── Commission_Tier__mdt/                  ← Tier metadata type
├── customMetadata/
│   ├── Commission_Plan.*.md-meta.xml          ← 5 plan records
│   └── Commission_Tier.*.md-meta.xml          ← 31 tier records
├── lwc/
│   ├── commissionPlanAdmin/                   ← Admin config screen
│   ├── commissionEntry/                       ← Data entry screen
│   └── repCommissionRecord/                   ← Record detail view
├── permissionsets/
│   └── Commission_Plan_Admin.permissionset-meta.xml
├── layouts/
│   └── Representative_Commission__c-Representative Commission Layout.layout-meta.xml
└── flexipages/
    ├── Commission_Entry.flexipage-meta.xml
    ├── Commission_Plan_Field_Config.flexipage-meta.xml
    └── Representative_Commission_Record_Page.flexipage-meta.xml
```
