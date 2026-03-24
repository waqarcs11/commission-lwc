trigger RepCommissionTrigger on Representative_Commission__c (before insert, before update) {
    // Skip Locked records — no changes allowed
    List<Representative_Commission__c> toProcess = new List<Representative_Commission__c>();
    for (Representative_Commission__c rec : Trigger.new) {
        if (rec.Status__c != 'Locked') {
            toProcess.add(rec);
        }
    }
    if (!toProcess.isEmpty()) {
        CommissionCalculationService.process(toProcess, Trigger.oldMap);
    }
}
