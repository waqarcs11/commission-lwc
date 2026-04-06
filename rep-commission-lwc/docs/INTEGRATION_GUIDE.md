# Commission LWC — Integration Guide

This document provides a full inventory of all Apex classes, objects, and fields in the Commission LWC package, along with the proposed integration pattern for fetching and writing commission data externally.

---

## Apex Classes

### 1. `CommissionEntryController`
**Type:** `public with sharing`
**Purpose:** Primary LWC controller — handles all UI-facing operations for commission entry, bulk run, and user plan assignment.

| Method | Type | Signature | Description |
|--------|------|-----------|-------------|
| `getActiveUsers` | `@AuraEnabled(cacheable=true)` | `List<UserOption> getActiveUsers()` | Returns all active Standard users with their assigned commission plan |
| `getUsersForPlan` | `@AuraEnabled(cacheable=true)` | `List<UserOption> getUsersForPlan(String planDeveloperName)` | Returns active Standard users assigned to a specific plan |
| `getCommissionPlans` | `@AuraEnabled(cacheable=true)` | `List<RC_Commission_Plan__mdt> getCommissionPlans()` | Returns all commission plans from custom metadata |
| `getFieldsForPlan` | `@AuraEnabled(cacheable=true)` | `List<FieldDetail> getFieldsForPlan(String planDeveloperName)` | Returns data-entry fields configured for a plan (excludes `_calc__c` fields), respects FLS |
| `getExistingRecord` | `@AuraEnabled` | `Representative_Commission__c getExistingRecord(String userId, String commissionDate, String planDeveloperName)` | Dynamic SOQL to fetch existing record with all configured fields pre-filled |
| `saveCommission` | `@AuraEnabled` | `String saveCommission(String userId, String commissionDate, String planDeveloperName, String fieldValuesJson, String existingRecordId)` | Create or update a commission record. Pass `existingRecordId` to update, null to create. Returns record Id |
| `runForMonth` | `@AuraEnabled` | `RunResult runForMonth(String planDeveloperName, String commissionDate)` | Bulk creates commission records for all users on a plan for a given month. Skips existing. Returns `{created, skipped}` |
| `saveUserPlans` | `@AuraEnabled` | `String saveUserPlans(String userPlansJson)` | Bulk updates `User.Commission_Plan__c`. Accepts JSON array of `{userId, userName, planDeveloperName}`. Returns `OK:N` or throws with error detail |

**Inner wrapper classes:**
- `UserOption` — `{id, name, commissionPlan}`
- `FieldDetail` — `{apiName, label, type}`
- `RunResult` — `{created, skipped}`

---

### 2. `CommissionCalculationService`
**Type:** `public with sharing`
**Purpose:** Trigger service — runs on `before insert / before update` on `Representative_Commission__c`. Calculates all commission components and writes results directly onto the record.

| Method | Signature | Description |
|--------|-----------|-------------|
| `process` | `void process(List<Representative_Commission__c> records, Map<Id, Representative_Commission__c> oldMap)` | Entry point called by trigger. Loads tiers, runs calculations, writes calc fields back onto records in memory |

**What it calculates (all written to `_Calc__c` fields):**

| Calc Field | Formula |
|---|---|
| `Attainment_Calc__c` | `(Funded_Units / Eligible_Units) * 100` — or `Approve_to_Fund_Ratio` for Proposed_Comp |
| `Tier_Lower_Calc__c` | Lower bound of matched tier |
| `Tier_Upper_Calc__c` | Upper bound of matched tier |
| `Tier_Payout_Calc__c` | Payout % or $ of matched tier |
| `Brokered_Commission_Calc__c` | `Brokered_Margin_Amount * (Brokered_Margin / 100)` |
| `Team_Closing_Ratio_Commission_Calc__c` | `>75%` = $3,000 / `70–75%` = $1,000 / else $0 |
| `Team_Margin_Commission_Calc__c` | `Team_Margin_Amount * (Team_Margin / 100)` |
| `Deal_Margin_Commission_Calc__c` | Plan-specific — % of Base Commission or flat tier dollar |
| `Termed_Deal_Commission_Calc__c` | `Termed_Deal_Margin_Amount * (Termed_Deal_Margin_Percentage / 100)` |
| `Cardiff_Commission_Calc__c` | `Cardiff_Deal_Margin_Amount * (Cardiff_Deal_Margin / 100)` |
| `Day60_Termed_Commission_Calc__c` | `Day60_Plus_Termed_Margin_Amount * (Day60_Plus_Termed_Margin / 100)` |
| `Proposed_Comp_Commission_Calc__c` | `Proposed_Comp_Margin * (tier% / 100) + X50K_Funded + X50KPlus_Funded` |
| `Commission_Amount_Calc__c` | Sum of all commission components |
| `Final_Commission_Calc__c` | `Commission_Amount_Calc + Commission_Adjustment` |

---

### 3. `CommissionPlanAdminController`
**Type:** `public with sharing`
**Purpose:** LWC controller for the Commission Plan Field Config admin screen.

| Method | Signature | Description |
|--------|-----------|-------------|
| `getPlans` | `List<RC_Commission_Plan__mdt> getPlans()` | Returns all commission plans |
| `getAvailableFields` | `List<FieldInfo> getAvailableFields()` | Returns all fields on `Representative_Commission__c` available for configuration |
| `getConfiguredFields` | `List<Commission_Plan_Field_Config__c> getConfiguredFields(String planDeveloperName)` | Returns fields already configured for a plan |
| `saveConfig` | `void saveConfig(String planDeveloperName, String fieldConfigJson)` | Saves field configuration for a plan |

---

### 4. `CommissionFieldConfigInstallHandler`
**Type:** `public`
**Purpose:** Post-install handler. Seeds default field configurations for all 6 plans if they don't already exist.

| Method | Signature | Description |
|--------|-----------|-------------|
| `onInstall` | `void onInstall(InstallContext ctx)` | Seeds default `Commission_Plan_Field_Config__c` records for all plans. Safe to re-run — skips plans already configured |

---

## Objects & Fields

### `Representative_Commission__c` — Core commission record
One record per rep per plan per month.

#### System / Tracking Fields
| Field API Name | Type | Description |
|---|---|---|
| `Name` | Text(80) | Auto-generated: `OwnerName - Plan Month-Year` |
| `OwnerId` | Lookup(User) | The rep this record belongs to |
| `Commission_Month__c` | Date | Always the 1st of the month (e.g. `2025-03-01`) |
| `Commission_Month_Year__c` | Text | Human-readable label (e.g. `March 2025`) |
| `Commission_Plan_Developer_Name__c` | Text | DeveloperName of the assigned plan (e.g. `Brokered_CRR_Comp`) |
| `Status__c` | Picklist | `Draft` / `Calculated` / `Approved` |

#### Data Entry Fields (entered manually by admin)
| Field API Name | Type | Used By Plan(s) |
|---|---|---|
| `Base_Commission__c` | Currency | Brokered_PM_Comp, Proposed_Comp |
| `Eligible_Units__c` | Number | All except Proposed_Comp |
| `Funded_Units__c` | Number | All except Proposed_Comp |
| `Brokered_Margin__c` | Percent | Cardiff_PM_Comp, Brokered_CRR_Comp (via ARD) |
| `Brokered_Margin_Amount__c` | Currency | Cardiff_PM_Comp, Assistant_Renewals_Director_Comp |
| `Team_Closing_Ratio__c` | Percent | Brokered_CRR_Comp, Assistant_Renewals_Director_Comp |
| `Team_Margin__c` | Percent | Brokered_CRR_Comp, CRF_CRR_Comp |
| `Team_Margin_Amount__c` | Currency | Brokered_CRR_Comp, CRF_CRR_Comp |
| `Termed_Deal_Margin_Percentage__c` | Percent | Cardiff_PM_Comp, Brokered_PM_Comp |
| `Termed_Deal_Margin_Amount__c` | Currency | Cardiff_PM_Comp, Brokered_PM_Comp |
| `Day60_Plus_Termed_Margin__c` | Percent | Brokered_CRR_Comp |
| `Day60_Plus_Termed_Margin_Amount__c` | Currency | Brokered_CRR_Comp |
| `Cardiff_Deal_Margin__c` | Percent | Cardiff_PM_Comp |
| `Cardiff_Deal_Margin_Amount__c` | Currency | Cardiff_PM_Comp |
| `Approve_to_Fund_Ratio__c` | Percent | Assistant_Renewals_Director_Comp, Proposed_Comp |
| `Proposed_Comp_Margin__c` | Currency | Proposed_Comp |
| `X50K_Funded__c` | Currency | Proposed_Comp |
| `X50KPlus_Funded__c` | Currency | Proposed_Comp |
| `Commission_Adjustment__c` | Currency | All plans |
| `Commission_Adjustment_Note__c` | Text | All plans |

#### Calculation Output Fields (written by trigger — do not set manually)
| Field API Name | Type | Description |
|---|---|---|
| `Attainment_Calc__c` | Percent | Funded/Eligible ratio |
| `Tier_Lower_Calc__c` | Percent | Matched tier lower bound |
| `Tier_Upper_Calc__c` | Percent | Matched tier upper bound |
| `Tier_Payout_Calc__c` | Percent/Currency | Matched tier payout value |
| `Brokered_Commission_Calc__c` | Currency | Brokered commission component |
| `Team_Closing_Ratio_Commission_Calc__c` | Currency | Team closing ratio bonus |
| `Team_Margin_Commission_Calc__c` | Currency | Team margin commission component |
| `Deal_Margin_Commission_Calc__c` | Currency | Deal margin component (plan-specific) |
| `Termed_Deal_Commission_Calc__c` | Currency | Termed deal commission component |
| `Cardiff_Commission_Calc__c` | Currency | Cardiff deal commission component |
| `Day60_Termed_Commission_Calc__c` | Currency | 60-day termed commission component |
| `Proposed_Comp_Commission_Calc__c` | Currency | Proposed comp total |
| `Commission_Amount_Calc__c` | Currency | Sum of all components |
| `Final_Commission_Calc__c` | Currency | `Commission_Amount + Adjustment` |

---

### `Commission_Plan_Field_Config__c` — Field configuration per plan
Controls which data entry fields are shown for each plan in the UI.

| Field API Name | Type | Description |
|---|---|---|
| `Commission_Plan_Developer_Name__c` | Text | Plan DeveloperName this config belongs to |
| `Field_API_Name__c` | Text | API name of the field on `Representative_Commission__c` |
| `Sort_Order__c` | Number | Display order in the UI |

---

### `RC_Commission_Plan__mdt` — Commission plans (Custom Metadata)
| Field API Name | Type | Description |
|---|---|---|
| `Label` | Text | Human-readable plan name |
| `DeveloperName` | Text | API name used throughout the system |
| `Payout_Type__c` | Text | `Percentage` or `FlatDollar` |

**Available plans:**
| DeveloperName | Label |
|---|---|
| `Cardiff_PM_Comp` | Cardiff PM Comp |
| `Brokered_PM_Comp` | Brokered PM Comp |
| `Brokered_CRR_Comp` | Brokered CRR Comp |
| `Assistant_Renewals_Director_Comp` | Assistant Renewals Director Comp |
| `CRF_CRR_Comp` | CRF CRR Comp |
| `Proposed_Comp` | Proposed Comp |

---

### `RC_Commission_Tier__mdt` — Commission tiers (Custom Metadata)
| Field API Name | Type | Description |
|---|---|---|
| `Commission_Plan__c` | MD Relationship | Parent plan |
| `Lowest_of_Funded_Unit_Against_Eligible__c` | Percent | Tier lower bound (attainment %) |
| `Upper_of_Funded_Units_Against_Eligible__c` | Percent | Tier upper bound (attainment %) |
| `Plan_Tier_Payout__c` | Number | Payout value (% or $ depending on plan) |
| `Payout_Type__c` | Text | `Percentage` or `FlatDollar` |

---

### `User` (standard object — extended)
| Field API Name | Type | Description |
|---|---|---|
| `Commission_Plan__c` | Text(255) | DeveloperName of the plan assigned to this rep |

---

## Proposed Integration Pattern

Based on your requirements — pass an array of rep IDs, get back all field values, write them to records — here is the recommended approach.

### What your class should do

```
Input:  List<Id> repIds  (User IDs)
           + String planDeveloperName
           + String commissionDate  (e.g. '2025-03-01')

Output: Map<Id, Representative_Commission__c>
           — keyed by rep User ID
           — each value contains the commission record with all data entry
             and calc fields populated
```

### How to fetch the data

```apex
// Step 1 — Get configured fields for the plan
List<Commission_Plan_Field_Config__c> configs = [
    SELECT Field_API_Name__c
    FROM Commission_Plan_Field_Config__c
    WHERE Commission_Plan_Developer_Name__c = :planDeveloperName
    ORDER BY Sort_Order__c ASC NULLS LAST
];

// Step 2 — Build dynamic SELECT including all configured fields + calc fields
List<String> selectFields = new List<String>{
    'Id', 'OwnerId', 'Name', 'Status__c',
    'Commission_Month__c', 'Commission_Month_Year__c',
    'Commission_Plan_Developer_Name__c',
    // Calc fields — always include
    'Attainment_Calc__c', 'Tier_Lower_Calc__c', 'Tier_Upper_Calc__c',
    'Tier_Payout_Calc__c', 'Commission_Amount_Calc__c', 'Final_Commission_Calc__c',
    'Brokered_Commission_Calc__c', 'Team_Closing_Ratio_Commission_Calc__c',
    'Team_Margin_Commission_Calc__c', 'Deal_Margin_Commission_Calc__c',
    'Termed_Deal_Commission_Calc__c', 'Cardiff_Commission_Calc__c',
    'Day60_Termed_Commission_Calc__c', 'Proposed_Comp_Commission_Calc__c'
};

for (Commission_Plan_Field_Config__c cfg : configs) {
    selectFields.add(cfg.Field_API_Name__c);
}

Date monthDate = Date.valueOf(commissionDate);

String soql = 'SELECT ' + String.join(selectFields, ', ')
    + ' FROM Representative_Commission__c'
    + ' WHERE OwnerId IN :repIds'
    + ' AND Commission_Plan_Developer_Name__c = :planDeveloperName'
    + ' AND Commission_Month__c = :monthDate';

// Step 3 — Return as Map keyed by OwnerId
Map<Id, Representative_Commission__c> result = new Map<Id, Representative_Commission__c>();
for (Representative_Commission__c rec : Database.query(soql)) {
    result.put(rec.OwnerId, rec);
}
return result;
```

### Writing values back

Once your external system has populated the data entry fields, write them back by updating the records. The `before update` trigger on `Representative_Commission__c` will automatically recalculate all `_Calc__c` fields.

```apex
// Example: update a record with new field values
Representative_Commission__c rec = result.get(someUserId);
rec.Eligible_Units__c    = 120;
rec.Funded_Units__c      = 95;
rec.Brokered_Margin__c   = 15.5;
update rec;
// Trigger fires → all _Calc__c fields recalculated automatically
```

### Key rules for integration

| Rule | Detail |
|---|---|
| **Never set `_Calc__c` fields directly** | They are overwritten by the trigger on every save |
| **`Commission_Month__c` is always the 1st** | e.g. March 2025 = `2025-03-01` |
| **`Commission_Plan_Developer_Name__c` is case-sensitive** | Must match exactly (e.g. `Brokered_CRR_Comp`) |
| **Trigger fires on update** | Any write to a data entry field recalculates all components |
| **`Status__c` auto-sets to `Calculated`** | Unless already `Approved` — don't override Approved records |
| **One record per OwnerId + Plan + Month** | Enforced by the `runForMonth` bulk create logic |
