import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCommissionPlans from '@salesforce/apex/CommissionEntryController.getCommissionPlans';
import getUsersForPlan   from '@salesforce/apex/CommissionEntryController.getUsersForPlan';
import runForMonth       from '@salesforce/apex/CommissionEntryController.runForMonth';

export default class CommissionRun extends LightningElement {

    @track planOptions    = [];
    @track selectedPlan   = '';
    @track selectedMonth  = '';
    @track repList        = [];
    @track isLoadingReps  = false;
    @track isRunning      = false;
    @track resultCreated  = null;
    @track resultSkipped  = null;
    @track resultUpdated  = null;

    // ── Getters ───────────────────────────────────────────────────────────────

    get showRepList()  { return !!this.selectedPlan; }
    get hasReps()      { return this.repList.length > 0; }
    get repCount()     { return this.repList.length; }
    get showResult()   { return this.resultCreated !== null; }

    get isRunDisabled() {
        return !this.selectedPlan || !this.selectedMonth
            || this.isLoadingReps || this.isRunning || !this.hasReps;
    }

    // The commission date sent to Apex is always the 1st of the selected month
    get commissionDate() {
        return this.selectedMonth ? this.selectedMonth + '-01' : '';
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        getCommissionPlans()
            .then(plans => {
                this.planOptions = plans.map(p => ({ label: p.Label, value: p.DeveloperName }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'));
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handlePlanChange(event) {
        this.selectedPlan  = event.detail.value;
        this.resultCreated = null;
        this.resultSkipped = null;
        this.resultUpdated = null;
        this.loadReps();
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.resultCreated = null;
        this.resultSkipped = null;
        this.resultUpdated = null;
    }

    handleRun() {
        this.isRunning = true;
        this.resultCreated = null;
        this.resultSkipped = null;
        this.resultUpdated = null;

        runForMonth({
            planDeveloperName : this.selectedPlan,
            commissionDate    : this.commissionDate
        })
            .then(result => {
                this.resultCreated = result.created;
                this.resultSkipped = result.skipped;
                this.resultUpdated = result.updated;
                this.loadReps();
                this.showToast(
                    'Run Complete',
                    `${result.created} created · ${result.updated} updated (targets refreshed) · ${result.skipped} skipped.`,
                    'success'
                );
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isRunning = false; });
    }

    handleReset() {
        this.selectedPlan   = '';
        this.selectedMonth  = '';
        this.repList        = [];
        this.resultCreated  = null;
        this.resultSkipped  = null;
        this.resultUpdated  = null;
    }

    // ── Private ───────────────────────────────────────────────────────────────

    loadReps() {
        if (!this.selectedPlan) return;
        this.isLoadingReps = true;
        getUsersForPlan({ planDeveloperName: this.selectedPlan })
            .then(users => {
                this.repList = users.map(u => ({ id: u.id, name: u.name }));
            })
            .catch(error => this.showToast('Error', this.extractMessage(error), 'error'))
            .finally(() => { this.isLoadingReps = false; });
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
