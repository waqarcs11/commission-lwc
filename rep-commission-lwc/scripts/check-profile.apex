User u = [SELECT Id, Name, ProfileId, Profile.Name FROM User WHERE IsActive = true AND Name = 'waqar khan' LIMIT 1];
System.debug('Profile: ' + u.Profile.Name + ' | ProfileId: ' + u.ProfileId);
