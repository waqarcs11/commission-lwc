import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPlans              from '@salesforce/apex/CommissionPlanAdminController.getPlans';
import getTiersForPlanWithId from '@salesforce/apex/CommissionPlanAdminController.getTiersForPlanWithId';
import savePlan              from '@salesforce/apex/CommissionPlanAdminController.savePlan';
import saveTier              from '@salesforce/apex/CommissionPlanAdminController.saveTier';
import deleteTier            from '@salesforce/apex/CommissionPlanAdminController.deleteTier';

const PAYOUT_TYPE_OPTIONS = [
    { label: 'Percentage', value: 'Percentage' },
    { label: 'Flat Dollar', value: 'FlatDollar' }
];

const TIER_PAYOUT_TYPE_OPTIONS = [
    { label: 'Percent',  value: 'Percent'  },
    { label: 'Currency', value: 'Currency' }
];

export default class CommissionPlanManager extends LightningElement {

    @track plans             = [];
    @track tiers             = [];
    @track selectedPlan      = null;
    @track isLoadingPlans    = false;
    @track isLoadingTiers    = false;
    @track isSavingPlan      = false;
    @track isSavingTier      = false;
    @track showAddPlanForm   = false;
    @track showAddTierForm   = false;

    // Add plan form fields
    @track newPlanName        = '';
    @track newPlanDevName     = '';
    @track newPlanPayoutType  = 'Percentage';

    // Add tier form fields
    @track newTierLower       = '';
    @track newTierUpper       = '';
    @track newTierPayout      = '';
    @track newTierPayoutType  = 'Currency';

    payoutTypeOptions     = PAYOUT_TYPE_OPTIONS;
    tierPayoutTypeOptions = TIER_PAYOUT_TYPE_OPTIONS;

    get hasTiers()          { return this.tiers.length > 0; }
    get hasPlans()          { return this.plans.length > 0; }
    get selectedPlanLabel() { return this.selectedPlan ? this.selectedPlan.Label : ''; }
    get addPlanLabel()      { return this.showAddPlanForm ? 'Cancel' : '+ Add Plan'; }
    get addPlanVariant()    { return this.showAddPlanForm ? 'neutral' : 'brand'; }
    get addTierLabel()      { return this.showAddTierForm ? 'Cancel' : '+ Add Tier'; }
    get addTierVariant()    { return this.showAddTierForm ? 'neutral' : 'brand'; }

    get isSavePlanDisabled() {
        return this.isSavingPlan || !this.newPlanName || !this.newPlanDevName;
    }

    get isSaveTierDisabled() {
        return this.isSavingTier
            || this.newTierLower === ''
            || this.newTierUpper === ''
            || this.newTierPayout === '';
    }

    connectedCallback() {
        this.loadPlans();
    }

    loadPlans() {
        this.isLoadingPlans = true;
        getPlans()
            .then(data => {
                this.plans = data.map(p => ({ ...p, cssClass: 'plan-row' }));
                // Re-highlight selected plan if still in list
                if (this.selectedPlan) {
                    this.plans = this.plans.map(p =>
                        p.DeveloperName === this.selectedPlan.DeveloperName
                            ? { ...p, cssClass: 'plan-row plan-row_selected' }
                            : p
                    );
                }
            })
            .catch(err => this.showToast('Error', this.extractMessage(err), 'error'))
            .finally(() => { this.isLoadingPlans = false; });
    }

    loadTiers() {
        if (!this.selectedPlan) return;
        this.isLoadingTiers = true;
        getTiersForPlanWithId({ planDeveloperName: this.selectedPlan.DeveloperName })
            .then(data => { this.tiers = data; })
            .catch(err => this.showToast('Error', this.extractMessage(err), 'error'))
            .finally(() => { this.isLoadingTiers = false; });
    }

    handleSelectPlan(event) {
        const devName = event.currentTarget.dataset.devname;
        this.selectedPlan = this.plans.find(p => p.DeveloperName === devName);
        this.plans = this.plans.map(p => ({
            ...p,
            cssClass: p.DeveloperName === devName ? 'plan-row plan-row_selected' : 'plan-row'
        }));
        this.tiers = [];
        this.showAddTierForm = false;
        this.loadTiers();
    }

    handleToggleAddPlan() {
        this.showAddPlanForm = !this.showAddPlanForm;
        if (!this.showAddPlanForm) this.resetPlanForm();
    }

    handleToggleAddTier() {
        this.showAddTierForm = !this.showAddTierForm;
        if (!this.showAddTierForm) this.resetTierForm();
    }

    handlePlanNameChange(event) {
        this.newPlanName = event.detail.value;
        // Auto-generate developer name from label (replace spaces with _, remove special chars)
        this.newPlanDevName = this.newPlanName
            .replace(/[^a-zA-Z0-9 ]/g, '')
            .trim()
            .replace(/ +/g, '_');
    }

    handlePlanDevNameChange(event)    { this.newPlanDevName    = event.detail.value; }
    handlePlanPayoutTypeChange(event) { this.newPlanPayoutType = event.detail.value; }
    handleTierLowerChange(event)      { this.newTierLower      = event.detail.value; }
    handleTierUpperChange(event)      { this.newTierUpper      = event.detail.value; }
    handleTierPayoutChange(event)     { this.newTierPayout     = event.detail.value; }
    handleTierPayoutTypeChange(event) { this.newTierPayoutType = event.detail.value; }

    handleSavePlan() {
        this.isSavingPlan = true;
        savePlan({
            name         : this.newPlanName,
            developerName: this.newPlanDevName,
            payoutType   : this.newPlanPayoutType
        })
            .then(() => {
                this.showToast('Success', `Plan "${this.newPlanName}" saved.`, 'success');
                this.showAddPlanForm = false;
                this.resetPlanForm();
                this.loadPlans();
            })
            .catch(err => this.showToast('Error', this.extractMessage(err), 'error'))
            .finally(() => { this.isSavingPlan = false; });
    }

    handleSaveTier() {
        this.isSavingTier = true;
        saveTier({
            planDeveloperName: this.selectedPlan.DeveloperName,
            lower    : parseFloat(this.newTierLower),
            upper    : parseFloat(this.newTierUpper),
            payout   : parseFloat(this.newTierPayout),
            payoutType: this.newTierPayoutType
        })
            .then(() => {
                this.showToast('Success', 'Tier added.', 'success');
                this.showAddTierForm = false;
                this.resetTierForm();
                this.loadTiers();
            })
            .catch(err => this.showToast('Error', this.extractMessage(err), 'error'))
            .finally(() => { this.isSavingTier = false; });
    }

    handleDeleteTier(event) {
        const tierId = event.currentTarget.dataset.id;
        deleteTier({ tierId })
            .then(() => {
                this.showToast('Deleted', 'Tier removed.', 'success');
                this.loadTiers();
            })
            .catch(err => this.showToast('Error', this.extractMessage(err), 'error'));
    }

    resetPlanForm() {
        this.newPlanName = '';
        this.newPlanDevName = '';
        this.newPlanPayoutType = 'Percentage';
    }

    resetTierForm() {
        this.newTierLower = '';
        this.newTierUpper = '';
        this.newTierPayout = '';
        this.newTierPayoutType = 'Currency';
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
