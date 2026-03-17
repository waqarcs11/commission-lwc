# Commission Plan Admin — Page Setup Guide

After deploying the package to your org, follow these steps to make the admin screen visible and restrict it to System Administrators only.

---

## Prerequisites

Ensure the deployment has succeeded. The following components must be present in your org:

- Apex class: `CommissionPlanAdminController`
- LWC component: `commissionPlanAdmin`
- Custom object: `Commission_Plan_Field_Config__c`
- Permission set: `Commission Plan Admin Access`

---

## Step 1 — Create the Lightning App Page

1. Go to **Setup** → search **"Lightning App Builder"** → click it
2. Click **New**
3. Select **App Page** → click **Next**
4. Enter the label: `Commission Plan Admin` → click **Next**
5. Select **One Region** (single column full-width layout) → click **Finish**

---

## Step 2 — Add the Component to the Page

6. In the App Builder canvas, look at the left panel under **Custom** components
7. Find **`commissionPlanAdmin`**
8. **Drag and drop** it onto the page canvas
9. Click **Save**

---

## Step 3 — Activate the Page

10. Click the **Activation** button (top right)
11. On the **App** tab → click **Add App** → select or create the **Commission Plan Admin** app
12. On the **Form Factor** tab → select **Desktop**
13. Click **Save** → click **Finish**

---

## Step 4 — Create a Lightning App (Admin-Only)

14. Go to **Setup** → search **"App Manager"** → click it
15. Click **New Lightning App** (top right)
16. Fill in:
    - App Name: `Commission Plan Admin`
    - Developer Name: auto-filled
    - App Icon: choose any (e.g., Gears)
17. Click **Next** through Navigation Items → add the **Commission Plan Admin** tab
18. On the **User Profiles** step → **remove all profiles** except **System Administrator**
19. Click **Save & Finish**

---

## Step 5 — Assign the Permission Set to Admins

20. Go to **Setup** → search **"Permission Sets"** → click it
21. Find **Commission Plan Admin Access** → click it
22. Click **Manage Assignments** → click **Add Assignments**
23. Select the System Administrator users who should have access → click **Assign**

---

## Step 6 — Verify Access

24. Log in as (or switch to) a System Administrator user
25. Open the **App Launcher** (9-dot grid, top left)
26. Search for **Commission Plan Admin** → click the app
27. The **Commission Plan Field Configuration** screen should appear with:
    - A dropdown to select a Commission Plan
    - Checkboxes for each field on Representative Commission
    - A **Save Configuration** button

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Component not visible in App Builder | Confirm `commissionPlanAdmin` LWC was deployed successfully |
| "Insufficient Privileges" error | Assign the `Commission Plan Admin Access` permission set to the user |
| No plans in the dropdown | Add records to `Commission_Plan__mdt` via **Setup → Custom Metadata Types** |
| No fields shown after selecting a plan | Verify `Representative_Commission__c` fields have FLS read access for the user's profile |
