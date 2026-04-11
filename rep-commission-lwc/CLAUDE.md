# Project Instructions

This is a Salesforce DX project.

---

## Goal
Build an admin LWC system for commission data entry and bulk commission run management.

---

## Business Context
- Commission plans are stored in custom metadata: `RC_Commission_Plan__mdt` (fields: Label, DeveloperName, Payout_Type__c)
- Plan tiers are stored in custom metadata: `Commission_Plan_Tier__mdt`
- Admin selects a plan and chooses which fields of `Representative_Commission__c` are visible for data entry
- Field config is stored in custom object: `Commission_Plan_Field_Config__c` (Field_API_Name__c, Commission_Plan_Developer_Name__c, Sort_Order__c, Metric_Type__c)
- `Metric_Type__c` picklist values include: `Month_Start_Target`, `Month_End_Target`, `Tier_Lookup_Input`, `Tier_Lookup_Output_Dollar`, `Tier_Lookup_Output_Assumption`, `User_Input_Assumption`, `Calculation_Input_Assumption`, `User_Input_Commission_Adjustment`, `Informational_Output_Value`, `Commission_Dollar_Output_Value`
- Each User has a custom field `Commission_Plan__c` (stores DeveloperName of their assigned plan)
- Calc fields ending in `_calc__c` on `Representative_Commission__c` are set by a trigger — never entered manually

---

## Architecture

### Apex: `CommissionEntryController.cls`
Single controller serving both LWC components. Key methods:
- `getActiveUsers()` — all active users with their Commission_Plan__c
- `getUsersForPlan(planDeveloperName)` — active users assigned to a specific plan
- `getCommissionPlans()` — all RC_Commission_Plan__mdt records
- `getFieldsForPlan(planDeveloperName)` — data-entry fields for a plan (excludes _calc__c fields), respects FLS
- `getExistingRecord(userId, commissionDate, planDeveloperName)` — dynamic SOQL to pre-fill existing record
- `saveCommission(userId, commissionDate, planDeveloperName, fieldValuesJson, existingRecordId)` — create or update
- `runForMonth(planDeveloperName, commissionDate)` — bulk create/update records for all reps on a plan; returns RunResult{created, skipped, updated}
  - New reps (no existing record): creates record with all field defaults applied
  - Existing reps: updates only fields where `Metric_Type__c` = `Month_Start_Target` or `Month_End_Target`; all other fields are left untouched
- `fetchBulkDefaults(reps, configs)` — private; accepts a list of configs (callers pass all configs or a filtered subset); seeds static defaults then overrides with report-driven values

### LWC: `commissionEntry`
2-step wizard for individual commission record entry:
- Step 1: Select rep (auto-selects their plan), month, plan
- Step 2: Dynamic fields loaded from field config; pre-fills if record exists; create or update mode
- Imports: getActiveUsers, getCommissionPlans, getFieldsForPlan, getExistingRecord, saveCommission

### LWC: `commissionRun` (NEW — on bulk-create branch)
Bulk commission run tool:
- Select a plan → shows list of reps assigned to it
- Select a month → click "Run for Month"
- Calls `runForMonth()` — creates records for new reps, updates Month Start/End Target fields on existing records
- Shows result: X created · Y updated (targets refreshed) · Z skipped
- Imports: getCommissionPlans, getUsersForPlan, runForMonth

### Tab: `Commission_Run.tab-meta.xml`
New tab for the commissionRun component.

---

## Technical Requirements
- Use LWC for UI
- Use Apex for loading custom metadata and saving config
- Respect FLS where possible
- Keep code modular and deployment-ready
- Prefer readable Apex and LWC code
- Add comments only where useful

---

## Current Branch: `bulk-create`
### Status (as of 2026-03-26)
**Modified:**
- `CommissionEntryController.cls` — added `getUsersForPlan()` and `runForMonth()` methods + `RunResult` wrapper class
- `commissionEntry.js` — (prior work, complete)
- `Commission_Management.app-meta.xml` — updated app config
- `Commission_Plan_Admin.permissionset-meta.xml` — updated permissions

**New / Untracked:**
- `lwc/commissionRun/` — new bulk-run LWC (html + js + meta.xml) — COMPLETE
- `objects/User/` — custom field Commission_Plan__c on User
- `tabs/Commission_Run.tab-meta.xml` — new tab for commissionRun

### What's done
- [x] commissionRun LWC built and wired to Apex
- [x] runForMonth Apex method written with skip-existing logic
- [x] getUsersForPlan Apex method written
- [x] runForMonth updated: existing reps now get Month Start/End Target fields refreshed instead of fully skipped
- [x] RunResult updated to include `updated` count alongside `created` and `skipped`
- [x] commissionRun LWC result banner updated to show created / updated / skipped counts
- [x] Deployed to cardiff-dtpfeb sandbox (waqar@datatoolspro.com.co.dtpfeb) — 2026-04-11

### Possibly pending
- [ ] Verify Commission_Run tab is wired to commissionRun component
- [ ] Test class for CommissionEntryController (runForMonth, getUsersForPlan)

---

## Session Log

### 2026-03-26
- Resumed project context from file inspection (no prior memory saved)
- Updated CLAUDE.md to capture full current state of bulk-create branch
- commissionRun LWC appears complete; controller has all needed methods

### 2026-04-11
- Updated runForMonth behaviour: existing reps no longer fully skipped
- Only fields with Metric_Type__c = Month_Start_Target or Month_End_Target are updated on existing records
- fetchBulkDefaults refactored to accept configs list as parameter (instead of querying internally) so callers can pass a filtered subset
- RunResult wrapper class updated with new `updated` field
- commissionRun LWC (html + js) updated to display updated count in result banner
- Deployed CommissionEntryController + commissionRun LWC to cardiff-dtpfeb
