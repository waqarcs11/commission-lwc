// Check if Commission_Plan__c is readable/writable on User
User u = [SELECT Id, Name, Commission_Plan__c FROM User WHERE IsActive = true LIMIT 1];
System.debug('Current user: ' + u.Name + ' | Commission_Plan__c = ' + u.Commission_Plan__c);

// Try writing to it
u.Commission_Plan__c = 'TEST_VALUE';
update u;

// Verify it saved
User updated = [SELECT Commission_Plan__c FROM User WHERE Id = :u.Id];
System.debug('After update: Commission_Plan__c = ' + updated.Commission_Plan__c);

// Clean up
u.Commission_Plan__c = null;
update u;
System.debug('Field is writable via Apex.');
