// Assign Commission Management app to System Administrator profile
Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
AppMenuItem app = [SELECT Id, ApplicationId FROM AppMenuItem WHERE Name = 'Commission_Management' LIMIT 1];
System.debug('App found: ' + app.ApplicationId + ' | Profile: ' + p.Id);
