# Project Instructions

This is a Salesforce DX project.

Goal:
Build an admin LWC for commission plan field configuration.

Business context:
- Plans are stored in custom metadata: Commission_Plan__mdt
- Plan tiers are stored in custom metadata: Commission_Plan_Tier__mdt
- Admin should select a plan and choose which fields of Rep_Commission__c are visible for data entry
- Mapping should be stored in custom object: Commission_Plan_Field_Config__c

Technical requirements:
- Use LWC for UI
- Use Apex for loading custom metadata and saving config
- Respect FLS where possible
- Keep code modular and deployment-ready
- Prefer readable Apex and LWC code
- Add comments only where useful

Expected deliverables:
- Apex controller for admin config
- LWC for plan selection and field mapping
- Metadata files for deployment
- Optional test class