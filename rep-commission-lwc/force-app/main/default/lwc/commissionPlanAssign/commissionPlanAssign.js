import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveUsers     from '@salesforce/apex/CommissionEntryController.getActiveUsers';
import getCommissionPlans from '@salesforce/apex/CommissionEntryController.getCommissionPlans';
import saveUserPlans      from '@salesforce/apex/CommissionEntryController.saveUserPlans';

export default class CommissionPlanAssign extends LightningElement {

    @track userRows    = [];  // { userId, userName, savedPlan, currentPlan, isDirty, rowClass }
    @track planOptions = [];  // { label, value } — value='' means unassign
    @track isLoading   = true;
    @track isSaving    = false;

    // ── Getters ───────────────────────────────────────────────────────────────

    get hasDirtyRows() {
        return this.userRows.some(r => r.isDirty);
    }

    get dirtyCount() {
        return this.userRows.filter(r => r.isDirty).length;
    }

    get saveButtonLabel() {
        const n = this.dirtyCount;
        return n > 0 ? `Save Changes (${n})` : 'Save Changes';
    }

    get isSaveDisabled() {
        return !this.hasDirtyRows || this.isSaving;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        Promise.all([
            getActiveUsers(),
            getCommissionPlans()
        ])
            .then(([users, plans]) => {
                this.planOptions = [
                    { label: '-- None --', value: '' },
                    ...plans.map(p => ({ label: p.Label, value: p.DeveloperName }))
                ];

                this.userRows = users.map(u => {
                    const plan = u.commissionPlan ?? '';
                    return {
                        userId      : u.id,
                        userName    : u.name,
                        savedPlan   : plan,
                        currentPlan : plan,
                        isDirty     : false,
                        rowClass    : 'slds-hint-parent'
                    };
                });
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handlePlanChange(event) {
        const userId  = event.target.dataset.userid;
        const newPlan = event.detail.value;

        this.userRows = this.userRows.map(row => {
            if (row.userId !== userId) return row;
            const isDirty = newPlan !== row.savedPlan;
            return {
                ...row,
                currentPlan : newPlan,
                isDirty     : isDirty,
                rowClass    : isDirty ? 'slds-hint-parent dirty-row' : 'slds-hint-parent'
            };
        });
    }

    handleSave() {
        const dirtyRows = this.userRows.filter(r => r.isDirty);
        if (dirtyRows.length === 0) return;

        const payload = dirtyRows.map(r => ({
            userId           : r.userId,
            userName         : r.userName,
            planDeveloperName: r.currentPlan   // '' → null in Apex (unassign)
        }));

        this.isSaving = true;

        saveUserPlans({ userPlansJson: JSON.stringify(payload) })
            .then(() => {
                // Commit — clear dirty flags and update savedPlan
                this.userRows = this.userRows.map(row => {
                    if (!row.isDirty) return row;
                    return {
                        ...row,
                        savedPlan : row.currentPlan,
                        isDirty   : false,
                        rowClass  : 'slds-hint-parent'
                    };
                });
                this.showToast('Success', `${dirtyRows.length} user plan(s) updated.`, 'success');
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isSaving = false; });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    extractMessage(error) {
        if (error?.body?.message)                        return error.body.message;
        if (error?.body?.output?.errors?.[0]?.message)  return error.body.output.errors[0].message;
        if (error?.message)                              return error.message;
        return 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
