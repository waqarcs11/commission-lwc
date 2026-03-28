# Commission LWC — Post-Install Setup Guide

## Package Information

| | |
|---|---|
| **Package Name** | Commission LWC |
| **Package ID** | 0HoPU00000004Ev0AI |
| **Latest Version** | 1.1.0-1 |
| **Version ID** | 04tPU000002KC5VYAW |
| **Installation URL** | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tPU000002KC5VYAW |

To install via Salesforce CLI:
```bash
sf package install --package 04tPU000002KC5VYAW --target-org <your-org-alias> --wait 10
```

### Version History

| Version | Version ID | What's included |
|---------|------------|-----------------|
| 1.1.0-1 | 04tPU000002KC5VYAW | Bulk commission run, user plan assignment UI, auto tab visibility, system user fix |
| 1.0.0-4 | 04tPU000002JcEvYAK | Initial release — Commission entry, plan field config, calculation engine, tiers |

---

After installing the **Commission LWC** package, complete the following steps to make the system fully operational in your org.

---

## Step 1 — Assign the Permission Set

All users who will use this system (admins, managers, anyone entering commission data) need the **Commission Plan Admin** permission set.

1. Go to **Setup** → search **Permission Sets** → click it
2. Click **Commission Plan Admin**
3. Click **Manage Assignments** → **Add Assignments**
4. Select the users who need access → click **Assign**

> This grants access to the `Representative_Commission__c` and `Commission_Plan_Field_Config__c` objects and the required Apex classes.

---

## Step 2 — Make the Commission Management App Visible

The package installs a custom app called **Commission Management**. If it is not appearing in the App Launcher, assign it to your profile:

1. Go to **Setup** → search **App Manager** → click it
2. Find **Commission Management** in the list → click the dropdown arrow on the right → **Edit**
3. Click **User Profiles** in the left menu
4. Move your profile (e.g. System Administrator) to the **Selected Profiles** list
5. Click **Save**

After saving, open the **App Launcher** (9-dot grid, top left), search for **Commission Management**, and you should see these tabs:
- **Commission Entry** — for entering rep commission data one record at a time
- **Run Commissions** — for bulk-creating commission records for an entire team in one click
- **Commission Plan Field Config** — for admin field configuration

---

## Step 3 — Add Commission Plan Field to the User Page Layout

The package adds a **Commission Plan** field to the User object. This field stores which commission plan each rep is assigned to. It must be added to the User page layout manually so admins can set it when editing a user record.

1. Go to **Setup** → search **Object Manager** → click it
2. Click **User** → click **Page Layouts**
3. Click the layout in use (typically **"User Layout"**)
4. In the **Fields** palette at the top, find **Commission Plan**
5. Drag it onto the layout in a visible section (e.g. under "Additional Information")
6. Click **Save**

> Once added, go to **Setup → Users → Users**, open any user, and you will see the **Commission Plan** field. Enter the exact `DeveloperName` of their plan (e.g. `Brokered_CRR_Comp`). This is what the system uses to assign records to the correct plan.

> To find valid plan DeveloperNames, run this query in Developer Console → Query Editor:
> ```sql
> SELECT Label, DeveloperName FROM RC_Commission_Plan__mdt
> ```

---

## Step 5 — Seed the Default Field Configurations

The package includes pre-configured field selections for all 6 commission plans. Run the following code once in **Anonymous Apex** to apply the defaults.

1. Go to **Setup** → search **Anonymous Apex** (or Developer Console → Debug → Open Execute Anonymous Window)
2. Paste the following code and click **Execute**:

```apex
new CommissionFieldConfigInstallHandler().onInstall(null);
```

This will create the default field configuration for all plans:

| Plan | Fields Configured |
|------|-------------------|
| `Cardiff_PM_Comp` | Eligible Units, Funded Units, Cardiff Margin %, Cardiff Margin $, Brokered Margin %, Brokered Margin $, Termed Deal %, Termed Deal $, Adjustment, + calc fields |
| `Brokered_PM_Comp` | Base Commission, Eligible Units, Funded Units, Termed Deal %, Termed Deal $, Adjustment, + calc fields |
| `Brokered_CRR_Comp` | Eligible Units, Funded Units, Team Margin %, Team Margin $, 60-Day Termed %, 60-Day Termed $, Adjustment, + calc fields |
| `Assistant_Renewals_Director_Comp` | Eligible Units, Funded Units, Brokered Margin %, Brokered Margin $, Team Closing Ratio, Adjustment, + calc fields |
| `CRF_CRR_Comp` | Eligible Units, Funded Units, Team Margin %, Team Margin $, Adjustment, + calc fields |
| `Proposed_Comp` | $50K Funded, $50K+ Funded, Approve to Fund Ratio, Base Commission, + calc fields |

> **Safe to re-run:** If you run this more than once, it will not overwrite any existing configuration. It only seeds plans that have no configuration yet.

> **Customization:** You can change field selections at any time via the **Commission Plan Field Config** tab.

---

## Step 6 — Set Up the Record Detail Page

The package includes a custom Lightning Record Page called **Representative Commission Record Page**. After installation it exists in your org but is not yet active — you need to assign it as the default page for `Representative_Commission__c` records.

### Option A — Via Lightning App Builder (Recommended)

1. Go to **Setup** → search **Lightning App Builder** → click it
2. Find **Representative Commission Record Page** in the list → click **Edit**
3. Click **Activation** button (top right corner)
4. Click the **Org Default** tab
5. Click **Assign as Org Default**
6. Click **Save** → click **Finish**

### Option B — From a Record Directly

1. Navigate to the **Representative Commissions** tab and open any record
   *(If no records exist yet, create a test one from the Commission Entry tab first)*
2. Click the **gear icon** (⚙) at the top right of the page → **Edit Page**
3. In Lightning App Builder, you will see the current page layout
4. Click **Activation** (top right)
5. Click the **Org Default** tab → **Assign as Org Default**
6. Click **Save** → **Finish**

> After completing either option, every Representative Commission record will show the custom layout — only the data entry fields for the active plan, plus all calculated results below.

> **If the page still shows the standard layout after activation:** Go to Setup → Lightning App Builder → find **Representative Commission Record Page** → verify it contains the **repCommissionRecord** component in the main region. If it is missing, drag it from the Custom Components panel on the left onto the canvas, then Save and Activate again.

---

## Step 7 — Verify Everything Works

1. Open the **Commission Management** app from the App Launcher
2. Click the **Commission Plan Field Config** tab
   - Select a plan from the dropdown
   - You should see checkboxes for data entry fields (defaults already selected from Step 5)
3. Click the **Commission Entry** tab
   - Select a rep, a month, and a plan
   - Click Next — only the fields configured for that plan should appear
   - Enter values and click Submit
   - Open the created record — calculations should be filled in automatically
4. Click the **Run Commissions** tab
   - Select a plan — you should see the list of reps assigned to it
   - Select a month and click **Run for Month**
   - Records are created for all reps; anyone who already has one for that month is skipped

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Commission Management app not visible | App not assigned to profile | Complete Step 2 |
| "Insufficient Privileges" error | Permission set not assigned | Complete Step 1 |
| Commission Plan field not visible on User record | Field not added to User page layout | Complete Step 3 |
| Run Commissions tab shows no reps after selecting a plan | Commission Plan field not set on user records | Complete Step 3, then assign plans to users |
| No fields shown in Commission Entry after selecting a plan | Field config not seeded | Complete Step 5 |
| Commission Entry shows all fields instead of plan-specific ones | Record Page not set as Org Default | Complete Step 6 |
| Calculations are not populating | Record Page not set as Org Default | Complete Step 6 |
| No plans in the dropdown | RC_Commission_Plan__mdt records missing | Contact your package administrator |

---

## Uninstalling the Package

If you want to remove the package from your org, follow these steps in order.

> **Warning:** Uninstalling the package will permanently delete all `Representative_Commission__c` records and all `Commission_Plan_Field_Config__c` records. Export your data first if you need to keep it.

### Before You Uninstall

**1. Export your data (optional but recommended)**

If you want to keep a copy of your commission records:
1. Go to **Setup** → search **Data Export** → click it
2. Select `Representative_Commission__c` and `Commission_Plan_Field_Config__c`
3. Export and download the CSV files

**2. Deactivate the Record Page**

1. Open any **Representative Commission** record
2. Click the **gear icon** → **Edit Page**
3. Click **Activation** → **Org Default** tab → **Remove as Org Default**
4. Click **Save** → **Finish**

---

### Uninstall the Package

1. Go to **Setup** → search **Installed Packages** → click it
2. Find **Commission LWC** in the list
3. Click **Uninstall**
4. Salesforce will show a list of everything that will be removed — review it
5. Check the box **"Yes, I want to uninstall..."** at the bottom
6. Click **Uninstall**

The uninstall runs in the background. You will receive an email when it is complete. It typically takes a few minutes.

**What gets removed automatically:**
- All `Representative_Commission__c` records and the object itself
- All `Commission_Plan_Field_Config__c` records and the object itself
- All `RC_Commission_Plan__mdt` and `RC_Commission_Tier__mdt` metadata types and their records
- All Apex classes (`CommissionCalculationService`, `CommissionEntryController`, `CommissionPlanAdminController`, etc.)
- All Lightning Web Components (`commissionEntry`, `commissionRun`, `commissionPlanAdmin`, `repCommissionRecord`)
- The `Commission Management` custom app and its tabs
- The `Commission Plan Admin` permission set

---

## Support

For configuration changes or issues, contact your Salesforce administrator or the package provider.
