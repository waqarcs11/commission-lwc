import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveUsers          from '@salesforce/apex/CommissionEntryController.getActiveUsers';
import getCommissionPlans      from '@salesforce/apex/CommissionEntryController.getCommissionPlans';
import getFieldsForPlan        from '@salesforce/apex/CommissionEntryController.getFieldsForPlan';
import getExistingRecord       from '@salesforce/apex/CommissionEntryController.getExistingRecord';
import getDefaultValuesForUser from '@salesforce/apex/CommissionEntryController.getDefaultValuesForUser';
import saveCommission          from '@salesforce/apex/CommissionEntryController.saveCommission';

export default class CommissionEntry extends LightningElement {

    // ── Navigation ────────────────────────────────────────────────────────────
    @track currentStep = 1;

    // ── Step 1 ────────────────────────────────────────────────────────────────
    @track userOptions       = [];
    @track planOptions       = [];
    @track selectedUserId    = '';
    @track selectedUserName  = '';
    @track selectedMonth     = '';
    @track selectedPlan      = '';
    @track selectedPlanLabel = '';

    // ── Step 2 ────────────────────────────────────────────────────────────────
    @track dynamicFields    = [];
    @track isLoadingFields  = false;
    @track isSaving         = false;
    @track existingRecordId = null;   // null = create, non-null = update

    // ── Getters ───────────────────────────────────────────────────────────────

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }

    get isNextDisabled() {
        return !this.selectedUserId || !this.selectedMonth || !this.selectedPlan;
    }

    get isSubmitDisabled() {
        return this.isLoadingFields || this.isSaving || this.dynamicFields.length === 0;
    }

    get isExistingRecord() {
        return !!this.existingRecordId;
    }

    get submitLabel() {
        return this.existingRecordId ? 'Update Record' : 'Create Record';
    }

    get showDynamicFields() {
        return !this.isLoadingFields && this.dynamicFields.length > 0;
    }

    get noFieldsConfigured() {
        return !this.isLoadingFields && this.dynamicFields.length === 0;
    }

    get selectedMonthLabel() {
        if (!this.selectedMonth) return '';
        const [year, month] = this.selectedMonth.split('-');
        return new Date(year, month - 1, 1).toLocaleDateString('en-US', {
            month: 'long',
            year: 'numeric'
        });
    }

    // The commission date sent to Apex is always the 1st of the selected month
    get commissionDate() {
        return this.selectedMonth ? this.selectedMonth + '-01' : '';
    }

    get progressValue() { return this.currentStep === 1 ? 0 : 100; }
    get progressStyle()  { return `width: ${this.progressValue}%;`; }

    get step1Class() {
        return this.currentStep >= 1
            ? 'slds-progress__item slds-is-complete'
            : 'slds-progress__item';
    }
    get step2Class() {
        return this.currentStep >= 2
            ? 'slds-progress__item slds-is-active'
            : 'slds-progress__item';
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadUsers();
        this.loadPlans();
    }

    // ── Step 1 data loading ───────────────────────────────────────────────────

    loadUsers() {
        getActiveUsers()
            .then(users => {
                // Store commissionPlan alongside id/name so we can auto-select on user change
                this.userOptions = users.map(u => ({
                    label: u.name,
                    value: u.id,
                    commissionPlan: u.commissionPlan
                }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'));
    }

    loadPlans() {
        getCommissionPlans()
            .then(plans => {
                this.planOptions = plans.map(p => ({ label: p.Label, value: p.DeveloperName }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'));
    }

    // ── Step 1 handlers ───────────────────────────────────────────────────────

    handleUserChange(event) {
        this.selectedUserId   = event.detail.value;
        const match           = this.userOptions.find(u => u.value === this.selectedUserId);
        this.selectedUserName = match ? match.label : '';

        // Auto-select the plan assigned to this user if they have one
        if (match && match.commissionPlan) {
            this.selectedPlan = match.commissionPlan;
            const planMatch   = this.planOptions.find(p => p.value === this.selectedPlan);
            this.selectedPlanLabel = planMatch ? planMatch.label : this.selectedPlan;
        }
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
    }

    handlePlanChange(event) {
        this.selectedPlan  = event.detail.value;
        const match        = this.planOptions.find(p => p.value === this.selectedPlan);
        this.selectedPlanLabel = match ? match.label : '';
    }

    handleNext() {
        this.currentStep    = 2;
        this.existingRecordId = null;
        this.dynamicFields  = [];
        this.loadFieldsAndPrefill();
    }

    handleBack() {
        this.currentStep = 1;
    }

    // ── Step 2 data loading ───────────────────────────────────────────────────

    loadFieldsAndPrefill() {
        this.isLoadingFields = true;

        // Run field config, existing record check, and default values fetch in parallel
        Promise.all([
            getFieldsForPlan({ planDeveloperName: this.selectedPlan }),
            getExistingRecord({
                userId           : this.selectedUserId,
                commissionDate   : this.commissionDate,
                planDeveloperName: this.selectedPlan
            }),
            getDefaultValuesForUser({
                userId           : this.selectedUserId,
                planDeveloperName: this.selectedPlan
            })
        ])
            .then(([fields, existingRecord, defaultValues]) => {
                this.existingRecordId = existingRecord ? existingRecord.Id : null;

                this.dynamicFields = fields.map(f => ({
                    apiName  : f.apiName,
                    label    : f.label,
                    type     : f.type,
                    formatter: this.resolveFormatter(f.type),
                    step     : this.resolveStep(f.type),
                    // Existing record takes priority; for new records use report/static defaults
                    value    : existingRecord
                        ? (existingRecord[f.apiName] ?? null)
                        : (defaultValues[f.apiName] ?? null)
                }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isLoadingFields = false; });
    }

    // ── Step 2 handlers ───────────────────────────────────────────────────────

    handleFieldChange(event) {
        const apiName = event.target.dataset.field;
        const value   = event.detail.value;
        this.dynamicFields = this.dynamicFields.map(f =>
            f.apiName === apiName ? { ...f, value } : f
        );
    }

    handleSubmit() {
        // Build the field values payload — only include fields with a value entered
        const fieldValues = this.dynamicFields.reduce((acc, f) => {
            if (f.value !== null && f.value !== '' && f.value !== undefined) {
                acc[f.apiName] = f.value;
            }
            return acc;
        }, {});

        this.isSaving = true;

        saveCommission({
            userId           : this.selectedUserId,
            commissionDate   : this.commissionDate,
            planDeveloperName: this.selectedPlan,
            fieldValuesJson  : JSON.stringify(fieldValues),
            existingRecordId : this.existingRecordId
        })
            .then(recordId => {
                const action = this.existingRecordId ? 'updated' : 'created';
                this.showToast('Success', `Commission record ${action} successfully.`, 'success');
                this.existingRecordId = recordId;  // switch to update mode after first save
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isSaving = false; });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    resolveFormatter(type) {
        if (type === 'CURRENCY') return 'currency';
        if (type === 'PERCENT')  return 'percent-fixed';
        return '';
    }

    resolveStep(type) {
        if (type === 'INTEGER') return '1';
        return '0.01';
    }

    extractMessage(error) {
        return (error && error.body && error.body.message)
            ? error.body.message
            : 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
